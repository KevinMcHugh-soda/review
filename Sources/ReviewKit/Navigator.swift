import Foundation
import ReviewCore
import ReviewLSP
import ReviewProcess

/// Code navigation for one checkout: a language server per language, started
/// the first time it is needed, and every answer translated into
/// `CodeLocation`s.
public actor Navigator {
    public enum NavigationError: Error, CustomStringConvertible, Sendable {
        case unsupportedFile(String)
        case serverMissing(ServerKind)

        public var description: String {
            switch self {
            case .unsupportedFile(let path): "Navigation works in Go and TypeScript files; \(path) is neither."
            case .serverMissing(let kind): "No \(kind.displayName) is installed — see the tool status in the sidebar."
            }
        }
    }

    public let root: URL
    private let environment: ToolEnvironment
    private var servers: [ServerKind: Task<LanguageServer, any Error>] = [:]

    public init(root: URL, environment: ToolEnvironment) {
        self.root = root
        self.environment = environment
    }

    /// Starts the servers for these paths' languages now, so indexing
    /// overlaps with the reviewer reading rather than with their first click.
    public func warmUp(paths: [String]) {
        for kind in Set(paths.compactMap(ServerKind.init(path:))) {
            _ = server(kind)
        }
    }

    /// The server's status, as it changes. Empty until the server is started.
    public func statusUpdates(for kind: ServerKind) async -> AsyncStream<LanguageServer.Status>? {
        guard let task = servers[kind], let server = try? await task.value else { return nil }
        return await server.statusUpdates()
    }

    public var startedKinds: [ServerKind] { ServerKind.allCases.filter { servers[$0] != nil } }

    public func shutdown() async {
        for task in servers.values {
            await (try? task.value)?.shutdown()
        }
        servers.removeAll()
    }

    // MARK: Requests

    /// Positions are 1-based lines and UTF-16 columns, as `CodeLocation`.
    public func definition(path: String, line: Int, column: Int) async throws -> [CodeLocation] {
        try await locations(path) { try await $0.definition(in: $1, at: $2) }
            .at(line, column)
    }

    public func typeDefinition(path: String, line: Int, column: Int) async throws -> [CodeLocation] {
        try await locations(path) { try await $0.typeDefinition(in: $1, at: $2) }
            .at(line, column)
    }

    public func implementations(path: String, line: Int, column: Int) async throws -> [CodeLocation] {
        try await locations(path) { try await $0.implementation(in: $1, at: $2) }
            .at(line, column)
    }

    public func references(path: String, line: Int, column: Int) async throws -> [CodeLocation] {
        try await locations(path) { try await $0.references(in: $1, at: $2) }
            .at(line, column)
    }

    /// The symbol at a position as the root of a call tree, or nil when it is
    /// not something that can be called.
    public func callHierarchy(path: String, line: Int, column: Int) async throws -> Caller? {
        let (server, file) = try await prepare(path)
        let items = try await server.prepareCallHierarchy(in: file, at: Position(line: line - 1, character: column))
        return items.first.map { Caller(item: $0, kind: server.kind, callSites: []) }
    }

    public func callers(of caller: Caller) async throws -> [Caller] {
        let server = try await server(caller.kind).value
        return try await server.incomingCalls(to: caller.item).map { call in
            Caller(item: call.caller, kind: caller.kind, callSites: call.ranges.map { range in
                CodeLocation(lsp: Location(uri: call.caller.location.uri, range: range))
            })
        }
    }

    public func hover(path: String, line: Int, column: Int) async throws -> String? {
        let (server, file) = try await prepare(path)
        return try await server.hover(in: file, at: Position(line: line - 1, character: column))?.markdown
    }

    // MARK: Internals

    private func prepare(_ path: String) async throws -> (LanguageServer, URL) {
        guard let kind = ServerKind(path: path) else { throw NavigationError.unsupportedFile(path) }
        return (try await server(kind).value, file(path))
    }

    private func locations(
        _ path: String,
        _ request: @Sendable @escaping (LanguageServer, URL, Position) async throws -> [Location]
    ) async throws -> PendingLocations {
        let (server, file) = try await prepare(path)
        return PendingLocations(server: server, file: file, request: request)
    }

    /// A worktree path, or an absolute one — a file outside the checkout
    /// that a previous jump landed in.
    private func file(_ path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
    }

    private func server(_ kind: ServerKind) -> Task<LanguageServer, any Error> {
        if let existing = servers[kind] { return existing }
        let root = root
        let environment = environment
        let task = Task {
            guard let command = await ServerCommand.resolve(kind, environment: environment) else {
                throw NavigationError.serverMissing(kind)
            }
            let server = LanguageServer(kind: kind, command: command, root: root, environment: environment.variables)
            try await server.start()
            return server
        }
        servers[kind] = task
        return task
    }
}

/// A request waiting for its position; lets the call sites read
/// `locations(path) { … }.at(line, column)`.
private struct PendingLocations {
    let server: LanguageServer
    let file: URL
    let request: @Sendable (LanguageServer, URL, Position) async throws -> [Location]

    func at(_ line: Int, _ column: Int) async throws -> [CodeLocation] {
        try await request(server, file, Position(line: line - 1, character: column)).map(CodeLocation.init(lsp:))
    }
}

/// A node in a call tree: something that calls the node above it.
public struct Caller: Hashable, Sendable, Identifiable {
    let item: CallHierarchyItem
    let kind: ServerKind
    /// Where this caller makes the call; empty for the root.
    public let callSites: [CodeLocation]

    public var id: String { "\(item.location.uri)#\(item.location.range.start.line):\(item.location.range.start.character)" }
    public var name: String { item.name }
    public var detail: String? { item.detail }
    public var location: CodeLocation { CodeLocation(lsp: item.location) }
}

extension CodeLocation {
    init(lsp location: Location) {
        // Standardised so a path that came back through a symlink compares
        // equal to the same file reached directly.
        let file = (location.fileURL ?? URL(fileURLWithPath: location.uri)).standardizedFileURL
        self.init(
            file: file,
            line: location.range.start.line + 1,
            column: location.range.start.character,
            endLine: location.range.end.line + 1,
            endColumn: location.range.end.character
        )
    }
}
