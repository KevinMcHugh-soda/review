import Foundation
import ReviewProcess

public struct GitError: Error, Sendable, CustomStringConvertible {
    public let arguments: [String]
    public let status: Int32
    public let stderr: String

    public var description: String {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return "git \(arguments.first ?? "") failed (\(status)): \(message.isEmpty ? "no output" : message)"
    }
}

/// Runs git with the options this app depends on pinned, whatever the user's
/// own config says.
public struct GitClient: Sendable {
    let git: URL
    let environment: [String: String]
    /// Credentials come from `gh`, not whatever helper the user configured:
    /// `gh` is already required and signed in, and the managed clones are
    /// blobless, so even `cat-file` can need to fetch.
    let credentialHelper: [String]

    public init(git: URL, gh: URL?, environment: [String: String]) {
        self.git = git
        var environment = environment
        // Never block on a username prompt nobody can see.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        // Untranslated messages, so stderr reads the same everywhere.
        environment["LC_ALL"] = "C"
        self.environment = environment
        credentialHelper = gh.map { gh in
            // An empty value first clears helpers inherited from the user's
            // config, so only this one is asked.
            ["-c", "credential.helper=", "-c", "credential.helper=!'\(gh.path)' auth git-credential"]
        } ?? []
    }

    @discardableResult
    public func run(
        _ arguments: [String],
        in repository: URL? = nil,
        timeout: Duration = .seconds(600)
    ) async throws -> ProcessOutput {
        var full = credentialHelper
        full += ["-c", "core.quotePath=false"]
        if let repository { full += ["-C", repository.path] }
        full += arguments
        let output = try await Subprocess.run(git, full, environment: environment, timeout: timeout)
        guard output.succeeded else {
            throw GitError(arguments: arguments, status: output.status, stderr: output.stderrText)
        }
        return output
    }

    /// The patch between two commits, in the shape `UnifiedDiffParser` reads.
    ///
    /// Every option that changes the output format is spelled out, because
    /// config can change each of them: prefixes (`diff.noprefix`,
    /// `diff.mnemonicPrefix`), rename detection (`diff.renames`), context
    /// (`diff.context`), colour, external diff drivers and textconv filters.
    public func diff(from base: String, to head: String, in repository: URL) async throws -> String {
        let output = try await run(
            [
                "diff", "--no-color", "--no-ext-diff", "--no-textconv",
                "--src-prefix=a/", "--dst-prefix=b/",
                "--find-renames", "--unified=3",
                base, head, "--",
            ],
            in: repository
        )
        return output.stdoutText
    }

    public func mergeBase(_ base: String, _ head: String, in repository: URL) async throws -> String {
        try await run(["merge-base", base, head], in: repository)
            .stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A file's bytes at a commit; nil when the path does not exist there.
    public func contents(of path: String, at commit: String, in repository: URL) async throws -> Data? {
        do {
            return try await run(["cat-file", "blob", "\(commit):\(path)"], in: repository).stdout
        } catch let error as GitError where error.stderr.contains("does not exist") || error.stderr.contains("Not a valid object name") {
            return nil
        }
    }

    public func hasCommit(_ sha: String, in repository: URL) async -> Bool {
        (try? await run(["cat-file", "-e", "\(sha)^{commit}"], in: repository)) != nil
    }
}
