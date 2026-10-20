import Foundation

/// The environment child processes run with, taken from the user's login shell.
///
/// An app launched from Finder or the Dock inherits launchd's environment, not
/// the shell's: PATH is `/usr/bin:/bin:/usr/sbin:/sbin`, so `gopls` in
/// `~/go/bin`, `claude` in `~/.local/bin` and anything from Homebrew are all
/// missing. GOPATH, GOPRIVATE, GOFLAGS and NODE_OPTIONS go missing with them,
/// which breaks gopls on private modules even when it is found. Asking the
/// login shell once, at launch, is what terminal-centric editors do too.
public struct ToolEnvironment: Sendable {
    public let variables: [String: String]
    /// Where `variables` came from, for `review doctor`.
    public let source: Source

    public enum Source: Sendable, Equatable {
        case loginShell(String)
        /// The shell could not be asked; this process's own environment plus
        /// the usual tool directories.
        case fallback(reason: String)
    }

    public init(variables: [String: String], source: Source) {
        self.variables = variables
        self.source = source
    }

    /// Directories where the tools this app needs usually live. Appended to
    /// PATH only on the fallback path, so a working shell always wins.
    static let wellKnownDirectories = [
        "/opt/homebrew/bin", "/usr/local/bin", "~/go/bin", "~/.local/bin",
    ]

    private static let marker = "__REVIEW_ENV_BEGIN__"

    /// Runs `$SHELL -l -i -c env` and keeps what follows a marker.
    ///
    /// Interactive (`-i`) as well as login, because most people set PATH in
    /// `.zshrc`, which a login-only shell never reads. Interactive shells can
    /// print banners and prompts, hence the marker; they can also hang on a
    /// prompt, hence the timeout.
    public static func loginShell(timeout: Duration = .seconds(10)) async -> Self {
        let current = ProcessInfo.processInfo.environment
        let shell = current["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        do {
            let output = try await Subprocess.run(
                URL(fileURLWithPath: shell),
                ["-l", "-i", "-c", "printf '%s\\0' \(marker); /usr/bin/env -0"],
                environment: current,
                timeout: timeout
            )
            guard output.succeeded, let variables = parse(output.stdout), variables["PATH"] != nil else {
                return fallback(current, reason: "\(shell) exited \(output.status)")
            }
            return Self(variables: variables, source: .loginShell(shell))
        } catch {
            return fallback(current, reason: "\(error)")
        }
    }

    /// Parses NUL-separated `env -0` output that follows the marker.
    static func parse(_ data: Data) -> [String: String]? {
        let fields = data.split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        // Banners print before the marker, so the marker is the last field that
        // merely *ends* with it.
        guard let start = fields.lastIndex(where: { $0.hasSuffix(marker) }) else { return nil }

        let pairs = fields[(start + 1)...].compactMap { field -> (String, String)? in
            guard let equals = field.firstIndex(of: "=") else { return nil }
            return (String(field[..<equals]), String(field[field.index(after: equals)...]))
        }
        return Dictionary(pairs, uniquingKeysWith: { _, last in last })
    }

    static func fallback(_ current: [String: String], reason: String) -> Self {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = wellKnownDirectories.map { $0.replacingOccurrences(of: "~", with: home) }
        let path = ([current["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"] + extra).joined(separator: ":")
        var variables = current
        variables["PATH"] = path
        return Self(variables: variables, source: .fallback(reason: reason))
    }

    /// The first executable named `tool` on this environment's PATH.
    public func locate(_ tool: String) -> URL? {
        let fileManager = FileManager.default
        return (variables["PATH"] ?? "")
            .split(separator: ":")
            .lazy
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(tool) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
