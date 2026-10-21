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
    /// Set for one call, e.g. `GIT_INDEX_FILE`.
    var extraEnvironment: [String: String] = [:]

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
        input: Data? = nil,
        timeout: Duration = .seconds(600)
    ) async throws -> ProcessOutput {
        var full = credentialHelper
        full += ["-c", "core.quotePath=false"]
        if let repository { full += ["-C", repository.path] }
        full += arguments
        let output = try await Subprocess.run(
            git, full, environment: environment.merging(extraEnvironment) { _, extra in extra },
            input: input, timeout: timeout
        )
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
    public func diff(from base: String, to head: String, paths: [String] = [], in repository: URL) async throws -> String {
        let output = try await run(
            [
                "diff", "--no-color", "--no-ext-diff", "--no-textconv",
                "--src-prefix=a/", "--dst-prefix=b/",
                "--find-renames", "--unified=3",
                // Full blob ids, whatever `core.abbrev` says: viewed-file
                // tracking compares them across loads.
                "--full-index",
                base, head, "--",
            ] + paths,
            in: repository
        )
        return output.stdoutText
    }

    public enum MergeResult: Hashable, Sendable {
        /// The tree the merge would produce. Readable with `contents(of:at:)`
        /// like a commit — no commit, and so no committer identity, is needed.
        case clean(tree: String)
        case conflicted
    }

    /// What merging `head` into `base` would produce, without touching any
    /// working tree. git ≥ 2.38.
    public func mergeTree(base: String, head: String, in repository: URL) async throws -> MergeResult {
        do {
            let output = try await run(["merge-tree", "--write-tree", "--no-messages", base, head], in: repository)
            let tree = output.stdoutText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return .clean(tree: tree)
        } catch let error as GitError where error.status == 1 {
            // Exit 1 is "conflicts", not failure.
            return .conflicted
        }
    }

    public func mergeBase(_ base: String, _ head: String, in repository: URL) async throws -> String {
        try await run(["merge-base", base, head], in: repository)
            .stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The commit a ref names; nil when there is no such ref.
    public func commit(named ref: String, in repository: URL) async -> String? {
        let sha = try? await run(["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"], in: repository)
            .stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha?.isEmpty == false ? sha : nil
    }

    /// A file's bytes at a commit; nil when the path does not exist there.
    public func contents(of path: String, at commit: String, in repository: URL) async throws -> Data? {
        do {
            return try await run(["cat-file", "blob", "\(commit):\(path)"], in: repository).stdout
        } catch let error as GitError where error.stderr.contains("does not exist") || error.stderr.contains("Not a valid object name") {
            return nil
        }
    }

    /// The paths marked generated at a commit — `linguist-generated` set or
    /// `true` in a `.gitattributes`, which is what GitHub collapses.
    ///
    /// The clone is bare and git 2.39 has no `check-attr --source`, so the
    /// commit's tree is read into a throwaway index and `check-attr --cached`
    /// takes the attributes from there. No checkout, no working tree.
    public func generatedPaths(_ paths: [String], at commit: String, in repository: URL) async throws -> Set<String> {
        guard !paths.isEmpty else { return [] }
        let index = FileManager.default.temporaryDirectory.appendingPathComponent("review-attr-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: index) }
        var scoped = self
        scoped.extraEnvironment["GIT_INDEX_FILE"] = index.path
        try await scoped.run(["read-tree", commit], in: repository)
        let output = try await scoped.run(
            ["check-attr", "--cached", "-z", "--stdin", "linguist-generated"],
            in: repository,
            input: Data(paths.joined(separator: "\0").utf8)
        )
        // -z output: path NUL attribute NUL value NUL, repeated.
        let fields = output.stdout.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        return Set(stride(from: 0, to: fields.count - 2, by: 3).compactMap { offset in
            ["set", "true"].contains(fields[offset + 2]) ? fields[offset] : nil
        })
    }

    /// Paths marked generated at any of the commits. A PR's head is what it
    /// declares itself, but a branch cut before the base added a rule — say,
    /// for a code generator's output — should still get that rule, as the
    /// file is generated whichever side says so.
    public func generatedPaths(_ paths: [String], atAnyOf commits: [String], in repository: URL) async throws -> Set<String> {
        var generated: Set<String> = []
        for commit in Set(commits) {
            generated.formUnion(try await generatedPaths(paths, at: commit, in: repository))
        }
        return generated
    }

    public func hasCommit(_ sha: String, in repository: URL) async -> Bool {
        (try? await run(["cat-file", "-e", "\(sha)^{commit}"], in: repository)) != nil
    }
}
