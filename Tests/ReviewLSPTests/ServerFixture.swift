import Foundation
import ReviewLSP
import ReviewProcess
import Testing

/// A tiny project on disk and a running server for it.
struct ServerFixture {
    let root: URL
    let server: LanguageServer

    /// The login shell's environment, read once for every server test.
    static let environment = Task { await ToolEnvironment.loginShell() }

    /// Synchronous, because `.enabled(if:)` cannot await: asks the login
    /// shell directly whether any server for the language is on its PATH.
    static func isInstalled(_ kind: ServerKind) -> Bool {
        let candidates =
            switch kind {
            case .go: "gopls"
            case .typeScript: "tsgo tsc typescript-language-server"
            }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        process.arguments = ["-l", "-i", "-c", "for c in \(candidates); do command -v $c && exit 0; done; exit 1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func start(_ kind: ServerKind, files: [String: String]) async throws -> Self {
        // Resolved, so the root matches what servers report: /var/folders
        // is a symlink to /private/var/folders, and servers realpath it.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-lsp-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let environment = await environment.value
        let command = try #require(await ServerCommand.resolve(kind, environment: environment))
        let server = LanguageServer(kind: kind, command: command, root: root, environment: environment.variables)
        try await server.start()
        return Self(root: root, server: server)
    }

    func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    /// The position of the first occurrence of `needle` on the first line
    /// that contains `context` (or `needle` itself).
    func position(of needle: String, in path: String, onLineWith context: String? = nil) throws -> Position {
        let text = try String(contentsOf: url(path), encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let line = try #require(lines.firstIndex { $0.contains(context ?? needle) && $0.contains(needle) })
        let range = try #require(lines[line].range(of: needle))
        return Position(line: line, character: lines[line].utf16.distance(from: lines[line].startIndex, to: range.lowerBound))
    }

    /// The repository-relative path of a location, for readable expectations.
    func relativePath(_ location: Location) -> String? {
        guard let path = location.fileURL?.resolvingSymlinksInPath().path else { return nil }
        let prefix = root.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    func stop() async {
        await server.shutdown()
        try? FileManager.default.removeItem(at: root)
    }
}
