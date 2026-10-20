import Foundation
import Synchronization

/// One question for `claude -p`.
public struct ClaudeRequest: Sendable {
    public let prompt: String
    /// Appended to Claude Code's own system prompt: who it is helping, and
    /// what the PR is.
    public let systemPrompt: String
    /// An empty directory to run in. Never the checkout: see
    /// plans/claude-integration.md.
    public let workingDirectory: URL
    /// The only directories Claude can read.
    public let readableDirectories: [URL]
    public let resumeSessionID: String?

    public init(
        prompt: String, systemPrompt: String, workingDirectory: URL,
        readableDirectories: [URL], resumeSessionID: String?
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.workingDirectory = workingDirectory
        self.readableDirectories = readableDirectories
        self.resumeSessionID = resumeSessionID
    }
}

public enum ClaudeError: Error, Sendable, CustomStringConvertible {
    case launchFailed(String)
    /// Exited without a `result` line.
    case exited(status: Int32, stderr: String)
    case timedOut

    public var description: String {
        switch self {
        case .launchFailed(let reason): "claude could not start: \(reason)"
        case let .exited(status, stderr): "claude exited (\(status))" + (stderr.isEmpty ? "" : ": \(stderr)")
        case .timedOut: "claude did not finish in time."
        }
    }
}

/// Runs one turn of `claude -p` and streams what it says.
///
/// The flags are the safety boundary, each verified against the real CLI:
/// `--tools` leaves exactly Read, Grep and Glob; `--restricted` confines them
/// to the working directories and ignores settings files; running in an empty
/// directory with the checkout attached by `--add-dir` keeps a PR's own
/// `CLAUDE.md` from being read as instructions; `--strict-mcp-config` starts no
/// MCP servers.
public struct ClaudeClient: Sendable {
    let executable: URL
    let environment: [String: String]

    public init(executable: URL, environment: [String: String]) {
        self.executable = executable
        self.environment = environment
    }

    static func arguments(for request: ClaudeRequest) -> [String] {
        var arguments = [
            "-p", request.prompt,
            "--restricted",
            "--tools", "Read,Grep,Glob",
            "--strict-mcp-config",
            "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--append-system-prompt", request.systemPrompt,
        ]
        for directory in request.readableDirectories {
            arguments += ["--add-dir", directory.path]
        }
        if let session = request.resumeSessionID {
            arguments += ["--resume", session]
        }
        return arguments
    }

    /// Events until `.finished`. Cancelling the consuming task terminates the
    /// process.
    public func ask(_ request: ClaudeRequest, timeout: Duration = .seconds(600)) -> AsyncThrowingStream<ClaudeEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<ClaudeEvent, any Error>.makeStream()
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(for: request)
        process.environment = environment
        process.currentDirectoryURL = request.workingDirectory
        // A pipe left open makes `claude -p` wait for stdin and warn.
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        // Exit is reported through the handler, not `waitUntilExit`, because
        // `Process` is not Sendable and cannot be waited on from the reader.
        let exited = AsyncStream<Int32>.makeStream()
        let exit = ExitLatch()
        process.terminationHandler = { finished in
            exit.markExited()
            exited.continuation.yield(finished.terminationStatus)
            exited.continuation.finish()
        }

        do {
            try FileManager.default.createDirectory(at: request.workingDirectory, withIntermediateDirectories: true)
            try process.run()
        } catch {
            continuation.finish(throwing: ClaudeError.launchFailed(error.localizedDescription))
            return stream
        }

        let pid = process.processIdentifier
        let output = stdout.fileHandleForReading
        let errors = stderr.fileHandleForReading
        // Drained alongside stdout: a full stderr pipe would stall claude.
        let stderrTail = Task.detached {
            String(decoding: errors.readDataToEndOfFile().suffix(2000), as: UTF8.self)
        }
        let reader = Task.detached {
            var parser = ClaudeStreamParser()
            var finished = false
            while true {
                let chunk = output.availableData
                if chunk.isEmpty { break }
                for event in parser.append(chunk) {
                    if case .finished = event { finished = true }
                    continuation.yield(event)
                }
            }
            var status: Int32 = -1
            for await code in exited.stream { status = code }
            if finished {
                continuation.finish()
            } else {
                let tail = await stderrTail.value.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.finish(throwing: ClaudeError.exited(status: status, stderr: tail))
            }
        }
        let watchdog = Task.detached {
            try await Task.sleep(for: timeout)
            continuation.finish(throwing: ClaudeError.timedOut)
        }
        continuation.onTermination = { _ in
            watchdog.cancel()
            reader.cancel()
            // Ends the turn when the consumer stops listening or the watchdog
            // fires. Only while it runs: an exited pid can be reused.
            if !exit.hasExited { kill(pid, SIGTERM) }
        }
        return stream
    }
}

/// Set once by the termination handler, read from the cancellation path.
private final class ExitLatch: Sendable {
    private let state = Mutex(false)

    var hasExited: Bool { state.withLock { $0 } }

    func markExited() {
        state.withLock { $0 = true }
    }
}
