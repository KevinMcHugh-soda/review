import Foundation

/// One running language server for one directory tree.
///
/// Read-only by design: files are opened with their on-disk text and never
/// changed, so there is no `didChange` and no versioning to get wrong.
public actor LanguageServer {
    public enum Status: Sendable, Equatable {
        case starting
        /// The server reported work in progress — gopls loading packages,
        /// tsserver loading a project. Results may be partial until it ends.
        case indexing(String)
        case ready
        case failed(String)
    }

    public nonisolated let kind: ServerKind
    public nonisolated let root: URL
    public nonisolated let command: ServerCommand
    private let environment: [String: String]
    /// Made in `start`, once `self` exists for its handlers to capture.
    private var connection: LSPConnection?
    private var opened: Set<String> = []
    private var work: [String: String] = [:]
    private(set) public var status: Status = .starting
    private var statusObservers: [UUID: AsyncStream<Status>.Continuation] = [:]

    public init(kind: ServerKind, command: ServerCommand, root: URL, environment: [String: String]) {
        self.kind = kind
        self.root = root
        self.command = command
        self.environment = environment
    }

    /// Launches the server and completes the initialize handshake.
    public func start() async throws {
        let root = root
        let connection = LSPConnection(
            executable: command.executable,
            arguments: command.arguments,
            environment: environment,
            currentDirectory: root,
            serverRequestHandler: { method, params in
                Self.answer(method, params, root: root)
            },
            notificationHandler: { [weak self] method, params in
                guard method == "$/progress", let params else { return }
                Task { await self?.didReceiveProgress(params) }
            }
        )
        self.connection = connection
        do {
            try await connection.start()
            _ = try await running().request("initialize", initializeParams(), timeout: .seconds(120))
            try await connection.notify("initialized", [:])
            if work.isEmpty { setStatus(.ready) }
        } catch {
            setStatus(.failed("\(error)"))
            throw error
        }
    }

    /// Status changes, starting with the current one.
    public func statusUpdates() -> AsyncStream<Status> {
        let (stream, continuation) = AsyncStream<Status>.makeStream()
        let id = UUID()
        statusObservers[id] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    public func shutdown() async {
        if let connection {
            _ = try? await connection.request("shutdown", nil, timeout: .seconds(5))
            try? await connection.notify("exit")
            await connection.terminate()
        }
        for continuation in statusObservers.values { continuation.finish() }
        statusObservers.removeAll()
    }

    // MARK: Requests

    public func definition(in file: URL, at position: Position) async throws -> [Location] {
        try await locations("textDocument/definition", file, position)
    }

    public func typeDefinition(in file: URL, at position: Position) async throws -> [Location] {
        try await locations("textDocument/typeDefinition", file, position)
    }

    public func implementation(in file: URL, at position: Position) async throws -> [Location] {
        try await locations("textDocument/implementation", file, position)
    }

    public func references(in file: URL, at position: Position) async throws -> [Location] {
        try await open(file)
        var params = textDocumentPosition(file, position)
        params["context"] = ["includeDeclaration": false]
        let result = try await running().request("textDocument/references", .object(params))
        return try Self.decodeLocations(result, method: "textDocument/references")
    }

    public func prepareCallHierarchy(in file: URL, at position: Position) async throws -> [CallHierarchyItem] {
        try await open(file)
        let result = try await running().request("textDocument/prepareCallHierarchy", .object(textDocumentPosition(file, position)))
        guard case .array(let items) = result else { return [] }
        do {
            return try items.map(CallHierarchyItem.init(raw:))
        } catch {
            throw LSPError.unreadableResult(method: "textDocument/prepareCallHierarchy", detail: "\(error)")
        }
    }

    public func incomingCalls(to item: CallHierarchyItem) async throws -> [IncomingCall] {
        let result = try await running().request("callHierarchy/incomingCalls", ["item": item.raw])
        guard case .array(let calls) = result else { return [] }
        do {
            return try calls.map { call in
                IncomingCall(
                    caller: try CallHierarchyItem(raw: call["from"] ?? .null),
                    ranges: try (call["fromRanges"] ?? []).decode(as: [TextRange].self)
                )
            }
        } catch {
            throw LSPError.unreadableResult(method: "callHierarchy/incomingCalls", detail: "\(error)")
        }
    }

    public func hover(in file: URL, at position: Position) async throws -> Hover? {
        try await open(file)
        let result = try await running().request("textDocument/hover", .object(textDocumentPosition(file, position)))
        return Self.decodeHover(result)
    }

    // MARK: Internals

    private func running() throws -> LSPConnection {
        guard let connection else { throw LSPError.launchFailed("not started") }
        return connection
    }

    private func locations(_ method: String, _ file: URL, _ position: Position) async throws -> [Location] {
        try await open(file)
        let result = try await running().request(method, .object(textDocumentPosition(file, position)))
        return try Self.decodeLocations(result, method: method)
    }

    /// `didOpen` once per file, with its on-disk text.
    private func open(_ file: URL) async throws {
        let uri = file.absoluteString
        guard !opened.contains(uri) else { return }
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try await running().notify("textDocument/didOpen", [
            "textDocument": [
                "uri": .string(uri),
                "languageId": .string(kind.languageID(for: file.path)),
                "version": 1,
                "text": .string(text),
            ],
        ])
        opened.insert(uri)
    }

    private func textDocumentPosition(_ file: URL, _ position: Position) -> [String: JSONValue] {
        [
            "textDocument": ["uri": .string(file.absoluteString)],
            "position": ["line": .number(Double(position.line)), "character": .number(Double(position.character))],
        ]
    }

    private func initializeParams() -> JSONValue {
        let rootURI = JSONValue.string(root.absoluteString)
        var params: JSONValue = [
            "processId": .number(Double(ProcessInfo.processInfo.processIdentifier)),
            "clientInfo": ["name": "Review"],
            "rootUri": rootURI,
            "workspaceFolders": [["uri": rootURI, "name": .string(root.lastPathComponent)]],
            "capabilities": [
                // UTF-16 is LSP's default and NSString's native unit; saying
                // so explicitly stops a server from picking UTF-8.
                "general": ["positionEncodings": ["utf-16"]],
                "textDocument": [
                    "synchronization": ["didSave": false, "dynamicRegistration": false],
                    "definition": ["linkSupport": true],
                    "typeDefinition": ["linkSupport": true],
                    "implementation": ["linkSupport": true],
                    "references": [:],
                    "hover": ["contentFormat": ["markdown", "plaintext"]],
                    "callHierarchy": [:],
                ],
                "window": ["workDoneProgress": true],
                "workspace": ["configuration": true, "workspaceFolders": true],
            ],
        ]
        if case .object(var object) = params, let options = command.initializationOptions {
            object["initializationOptions"] = options
            params = .object(object)
        }
        return params
    }

    /// Answers the requests servers send the client. Anything unrecognised
    /// gets `null`, which every server tolerates; silence would stall them.
    private static func answer(_ method: String, _ params: JSONValue?, root: URL) -> JSONValue {
        switch method {
        case "workspace/configuration":
            // One settings object per item asked for; defaults throughout.
            guard case .array(let items) = params?["items"] ?? .null else { return [] }
            return .array(items.map { _ in [:] })
        case "workspace/workspaceFolders":
            return [["uri": .string(root.absoluteString), "name": .string(root.lastPathComponent)]]
        default:
            return .null
        }
    }

    private func didReceiveProgress(_ params: JSONValue) {
        let token = params["token"].map { $0.stringValue ?? "\($0)" } ?? ""
        let value = params["value"]
        switch value?["kind"]?.stringValue {
        case "begin":
            work[token] = value?["title"]?.stringValue ?? "Indexing"
        case "end":
            work[token] = nil
        default:
            return
        }
        if case .failed = status { return }
        setStatus(work.values.sorted().first.map(Status.indexing) ?? .ready)
    }

    private func setStatus(_ new: Status) {
        guard new != status else { return }
        status = new
        for continuation in statusObservers.values { continuation.yield(new) }
    }

    private func removeObserver(_ id: UUID) {
        statusObservers[id] = nil
    }

    // MARK: Decoding

    static func decodeLocations(_ result: JSONValue, method: String) throws -> [Location] {
        let items: [JSONValue] =
            switch result {
            case .null: []
            case .array(let array): array
            default: [result]
            }
        do {
            return try items.map { item in
                if item["targetUri"] != nil {
                    let link = try item.decode(as: LocationLink.self)
                    return Location(uri: link.targetUri, range: link.targetSelectionRange)
                }
                return try item.decode(as: Location.self)
            }
        } catch {
            throw LSPError.unreadableResult(method: method, detail: "\(error)")
        }
    }

    static func decodeHover(_ result: JSONValue) -> Hover? {
        func text(_ value: JSONValue) -> String? {
            switch value {
            case .string(let string): string
            case .object:
                // MarkupContent {kind, value} or MarkedString {language, value}.
                if let language = value["language"]?.stringValue, let code = value["value"]?.stringValue {
                    "```\(language)\n\(code)\n```"
                } else {
                    value["value"]?.stringValue
                }
            case .array(let parts): parts.compactMap(text).joined(separator: "\n\n")
            default: nil
            }
        }
        guard let contents = result["contents"], let markdown = text(contents), !markdown.isEmpty else { return nil }
        return Hover(markdown: markdown)
    }
}
