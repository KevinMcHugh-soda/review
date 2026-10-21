import Foundation
import ReviewProcess

public enum LSPError: Error, Sendable, CustomStringConvertible, Equatable {
    case launchFailed(String)
    /// The server answered with a JSON-RPC error.
    case response(code: Int, message: String)
    /// The server exited; every pending and later request fails with this.
    case serverExited(status: Int32, stderr: String)
    case timedOut(method: String)
    case unreadableResult(method: String, detail: String)

    public var description: String {
        switch self {
        case .launchFailed(let reason): "The language server could not start: \(reason)"
        case let .response(code, message): "The language server returned an error (\(code)): \(message)"
        case let .serverExited(status, stderr):
            "The language server exited (\(status))" + (stderr.isEmpty ? "." : ": \(stderr)")
        case .timedOut(let method): "The language server did not answer \(method) in time."
        case let .unreadableResult(method, detail): "The language server's answer to \(method) could not be read: \(detail)"
        }
    }
}

/// JSON-RPC over a child process's stdio.
///
/// One reader thread decodes frames from stdout and hands each message back
/// to the actor, which resolves the matching request or dispatches the
/// notification. Servers also send *requests* to the client —
/// `workspace/configuration`, `window/workDoneProgress/create` — and gopls
/// stalls until they are answered, so those go to `serverRequestHandler`.
public actor LSPConnection {
    public typealias ServerRequestHandler = @Sendable (_ method: String, _ params: JSONValue?) async -> JSONValue
    public typealias NotificationHandler = @Sendable (_ method: String, _ params: JSONValue?) -> Void

    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
    private var exitError: LSPError?
    /// The last stderr output, kept for the exit error. Servers log there
    /// freely, so only the tail is worth keeping.
    private var stderrTail = Data()
    private let serverRequestHandler: ServerRequestHandler
    private let notificationHandler: NotificationHandler

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL,
        serverRequestHandler: @escaping ServerRequestHandler,
        notificationHandler: @escaping NotificationHandler
    ) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectory
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        self.serverRequestHandler = serverRequestHandler
        self.notificationHandler = notificationHandler
    }

    public func start() throws(LSPError) {
        // Writing to a server that has died raises SIGPIPE, whose default
        // action kills this whole process. Ignored, the write fails with EPIPE
        // instead, which `send` turns into `serverExited`. Process-wide, and
        // harmless to repeat.
        signal(SIGPIPE, SIG_IGN)
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { await self?.didExit(status: status) }
        }
        do {
            try process.run()
        } catch {
            throw .launchFailed(error.localizedDescription)
        }

        let output = stdout.fileHandleForReading
        Task.detached { [weak self] in
            var decoder = FrameDecoder()
            for await chunk in output.chunks {
                guard let messages = try? decoder.append(chunk) else { return }
                for message in messages {
                    await self?.receive(message)
                }
            }
        }
        let errors = stderr.fileHandleForReading
        Task.detached { [weak self] in
            for await chunk in errors.chunks {
                await self?.appendStderr(chunk)
            }
        }
    }

    public var isRunning: Bool { process.isRunning }

    /// Sends a request and waits for its result. `null` is a valid result.
    public func request(_ method: String, _ params: JSONValue? = nil, timeout: Duration = .seconds(60)) async throws -> JSONValue {
        if let exitError { throw exitError }
        let id = nextID
        nextID += 1
        var message: [String: JSONValue] = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method)]
        if let params { message["params"] = params }
        try send(.object(message))

        let watchdog = Task { [weak self] in
            try await Task.sleep(for: timeout)
            await self?.fail(id: id, with: .timedOut(method: method))
        }
        defer { watchdog.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    public func notify(_ method: String, _ params: JSONValue? = nil) throws {
        if let exitError { throw exitError }
        var message: [String: JSONValue] = ["jsonrpc": "2.0", "method": .string(method)]
        if let params { message["params"] = params }
        try send(.object(message))
    }

    public func terminate() {
        if process.isRunning { process.terminate() }
    }

    // MARK: Internals

    private func send(_ message: JSONValue) throws {
        let data = try MessageFraming.encode(message)
        do {
            try stdin.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw exitError ?? LSPError.serverExited(status: -1, stderr: error.localizedDescription)
        }
    }

    private func receive(_ data: Data) async {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
        let method = message["method"]?.stringValue
        let id = message["id"]

        switch (method, id) {
        case let (method?, id?):
            // A request from the server.
            let result = await serverRequestHandler(method, message["params"])
            try? send(["jsonrpc": "2.0", "id": id, "result": result])
        case let (method?, nil):
            notificationHandler(method, message["params"])
        case let (nil, id?):
            guard let id = id.intValue, let continuation = pending.removeValue(forKey: id) else { return }
            if let error = message["error"] {
                continuation.resume(throwing: LSPError.response(
                    code: error["code"]?.intValue ?? 0,
                    message: error["message"]?.stringValue ?? "unknown error"
                ))
            } else {
                continuation.resume(returning: message["result"] ?? .null)
            }
        case (nil, nil):
            return
        }
    }

    private func fail(id: Int, with error: LSPError) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    /// LSP's own cancellation, so the server stops working on it too.
    private func cancel(id: Int) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
        try? notify("$/cancelRequest", ["id": .number(Double(id))])
    }

    private func appendStderr(_ chunk: Data) {
        stderrTail.append(chunk)
        if stderrTail.count > 8192 { stderrTail = stderrTail.suffix(4096) }
    }

    private func didExit(status: Int32) {
        let tail = String(decoding: stderrTail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let error = LSPError.serverExited(status: status, stderr: String(tail.suffix(600)))
        exitError = error
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
        pending.removeAll()
    }
}
