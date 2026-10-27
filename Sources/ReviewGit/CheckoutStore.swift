import Foundation
import ReviewCore

/// The app's own clones, one per repository, under Application Support.
///
/// Never the reviewer's working copy — see plans/checkout-and-diff.md. Clones
/// are bare and blobless: history arrives up front, file contents only as a
/// diff or a checkout asks for them.
public struct CheckoutStore: Sendable {
    public let root: URL
    let git: GitClient
    /// Where repositories are cloned from. GitHub in the app; a local path in
    /// tests.
    let remoteURL: @Sendable (PullRequestReference) -> String

    public init(
        root: URL,
        git: GitClient,
        remoteURL: @escaping @Sendable (PullRequestReference) -> String = { "https://github.com/\($0.repositorySlug).git" }
    ) {
        self.root = root
        self.git = git
        self.remoteURL = remoteURL
    }

    /// `~/Library/Application Support/Review`.
    public static var defaultRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Review", isDirectory: true)
    }

    public func repositoryPath(for reference: PullRequestReference) -> URL {
        root.appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent(reference.owner, isDirectory: true)
            .appendingPathComponent("\(reference.repository).git", isDirectory: true)
    }

    public func hasRepository(for reference: PullRequestReference) -> Bool {
        FileManager.default.fileExists(atPath: repositoryPath(for: reference).appendingPathComponent("HEAD").path)
    }

    /// Clones the repository if this is its first pull request.
    ///
    /// Clones into a temporary sibling and renames it into place, so an
    /// interrupted clone never leaves a half-made repository that a later open
    /// would mistake for a good one.
    public func ensureRepository(for reference: PullRequestReference) async throws -> URL {
        let path = repositoryPath(for: reference)
        guard !hasRepository(for: reference) else { return path }
        let fileManager = FileManager.default

        let parent = path.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".\(reference.repository)-\(UUID().uuidString).git")
        defer { try? fileManager.removeItem(at: staging) }

        try await git.run(
            ["clone", "--bare", "--filter=blob:none", "--quiet", remoteURL(reference), staging.path],
            timeout: .seconds(1800)
        )
        try fileManager.moveItem(at: staging, to: path)
        return path
    }

    /// Fetches the PR's head and its base branch, then confirms both commits
    /// GitHub named are present.
    ///
    /// The refs are written under `refs/review/` so they never collide with a
    /// branch, and so `git gc` keeps the commits alive.
    ///
    /// Fetches name `origin`, never the URL: a partial clone applies its
    /// blob filter only when fetching from its promisor remote, so fetching by
    /// URL quietly downloads every blob in the new history.
    /// Where `fetch` keeps the base branch's tip, which can be ahead of the
    /// API's `base.sha`: GitHub updates that only when the PR itself changes.
    public static func baseRef(_ branch: String) -> String { "refs/review/base/\(branch)" }

    public func fetch(_ pullRequest: PullRequest, into repository: URL) async throws {
        let number = pullRequest.reference.number
        try await git.run(
            [
                "fetch", "--quiet", "--no-tags", "--force", "origin",
                "refs/pull/\(number)/head:refs/review/pull/\(number)/head",
                "refs/heads/\(pullRequest.base.name):\(Self.baseRef(pullRequest.base.name))",
            ],
            in: repository
        )
        // The API and the fetch race: the author can push in between. Fetch
        // the exact commits by id if the refs moved past them.
        for sha in [pullRequest.head.sha, pullRequest.base.sha] {
            if await !git.hasCommit(sha, in: repository) {
                try await git.run(["fetch", "--quiet", "--no-tags", "origin", sha], in: repository)
            }
        }
    }

    public func worktreePath(for reference: PullRequestReference) -> URL {
        root.appendingPathComponent("worktrees", isDirectory: true)
            .appendingPathComponent(reference.owner, isDirectory: true)
            .appendingPathComponent(reference.repository, isDirectory: true)
            .appendingPathComponent(String(reference.number), isDirectory: true)
            .appendingPathComponent("head", isDirectory: true)
    }

    /// A checkout of the PR's head for the language servers, moved to the
    /// current head if the PR has gained commits since it was made.
    ///
    /// Detached, so no branch name collides across PRs, and forced, because
    /// nobody edits these: anything that differs from the commit is ours to
    /// overwrite. Returned with symlinks resolved, so it compares equal to the
    /// paths servers report.
    public func ensureWorktree(for pullRequest: PullRequest, repository: URL) async throws -> URL {
        let path = worktreePath(for: pullRequest.reference)
        let fileManager = FileManager.default
        let sha = pullRequest.head.sha

        if fileManager.fileExists(atPath: path.appendingPathComponent(".git").path) {
            let current = try? await git.run(["rev-parse", "HEAD"], in: path)
                .stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            if current != sha {
                try await git.run(["checkout", "--quiet", "--force", "--detach", sha], in: path)
            }
        } else {
            try fileManager.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            // A worktree deleted by hand leaves a registration behind that
            // makes `worktree add` refuse the path.
            try await git.run(["worktree", "prune"], in: repository)
            try await git.run(
                ["worktree", "add", "--quiet", "--force", "--detach", path.path, sha],
                in: repository,
                timeout: .seconds(1800)
            )
        }
        return path.resolvingSymlinksInPath()
    }

    public func removeWorktree(for reference: PullRequestReference, repository: URL) async {
        let path = worktreePath(for: reference)
        _ = try? await git.run(["worktree", "remove", "--force", path.path], in: repository)
    }
}
