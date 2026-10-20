import Foundation
import ReviewProcess

/// How to launch the server for a language, decided from what is installed.
public struct ServerCommand: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    let initializationOptions: JSONValue?
    /// What `review doctor` and the app show: "gopls v0.24.0",
    /// "TypeScript 7.0.2 (native)".
    public let summary: String

    /// Nil when nothing usable is installed for that language.
    ///
    /// For TypeScript there are two servers, and the order matters:
    ///
    /// 1. **TypeScript 7's own** (`tsgo`, or `tsc` from `typescript@7`),
    ///    run as `--lsp --stdio`. TypeScript 7 is the native rewrite and has
    ///    no `tsserver.js` at all, so it is the only option once it is the
    ///    global install — and the faster one.
    /// 2. **typescript-language-server**, which wraps a `tsserver.js`. It
    ///    looks in the workspace's `node_modules` first, which a PR checkout
    ///    never has (this app does not install a PR's dependencies), so it is
    ///    pointed at a global TypeScript 5 as a fallback when one exists.
    public static func resolve(_ kind: ServerKind, environment: ToolEnvironment) async -> Self? {
        switch kind {
        case .go:
            guard let gopls = environment.locate("gopls") else { return nil }
            let version = await firstLine(gopls, ["version"], environment) ?? "gopls"
            return Self(executable: gopls, arguments: [], initializationOptions: nil, summary: version)
        case .typeScript:
            return await typeScript(environment)
        }
    }

    private static func typeScript(_ environment: ToolEnvironment) async -> Self? {
        if let tsgo = environment.locate("tsgo") {
            let version = await firstLine(tsgo, ["--version"], environment) ?? ""
            return Self(executable: tsgo, arguments: ["--lsp", "--stdio"], initializationOptions: nil, summary: "tsgo \(version)")
        }
        let tsc = environment.locate("tsc")
        let tscVersion = await tsc.asyncMap { await firstLine($0, ["--version"], environment) } ?? nil
        if let tsc, let tscVersion, let major = majorVersion(tscVersion), major >= 7 {
            return Self(
                executable: tsc, arguments: ["--lsp", "--stdio"], initializationOptions: nil,
                summary: "TypeScript \(tscVersion.replacingOccurrences(of: "Version ", with: "")) (native)"
            )
        }
        guard let server = environment.locate("typescript-language-server") else { return nil }
        let fallback = tsc.flatMap(globalTSServerDirectory)
        return Self(
            executable: server,
            arguments: ["--stdio"],
            initializationOptions: fallback.map { ["tsserver": ["fallbackPath": .string($0.path)]] },
            summary: "typescript-language-server" + (tscVersion.map { " with \($0)" } ?? "")
        )
    }

    /// `Version 5.6.3` → 5.
    static func majorVersion(_ output: String) -> Int? {
        let digits = output.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    /// The `lib/` directory holding `tsserver.js`, found from the `tsc` on
    /// PATH: `bin/tsc` is a symlink into `…/node_modules/typescript/bin/`.
    private static func globalTSServerDirectory(_ tsc: URL) -> URL? {
        let lib = tsc.resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("lib", isDirectory: true)
        return FileManager.default.fileExists(atPath: lib.appendingPathComponent("tsserver.js").path) ? lib : nil
    }

    private static func firstLine(_ executable: URL, _ arguments: [String], _ environment: ToolEnvironment) async -> String? {
        guard let output = try? await Subprocess.run(
            executable, arguments, environment: environment.variables, timeout: .seconds(15)
        ), output.succeeded else { return nil }
        return output.stdoutText.split(whereSeparator: \.isNewline).first.map(String.init)
    }
}

extension Optional {
    fileprivate func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}
