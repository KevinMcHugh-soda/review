import Foundation
import ReviewCore
import ReviewDiff
import ReviewGit
import ReviewGitHub

/// A pull request ready to read: its metadata, the merge base, and every
/// changed file's diff.
public struct LoadedReview: Sendable {
    public let pullRequest: PullRequest
    /// Where the diff starts — GitHub's three-dot diff is merge base → head.
    public let mergeBase: String
    public let files: [FileDiff]
    let repository: URL
    let git: GitClient

    /// One side of a file as text; nil when it does not exist on that side.
    /// Bytes that are not UTF-8 are replaced rather than failing the file.
    public func text(of file: FileDiff, on side: Side) async throws -> String? {
        let (path, commit) =
            switch side {
            case .base: (file.oldPath, mergeBase)
            case .head: (file.newPath, pullRequest.head.sha)
            }
        guard let path, let data = try await git.contents(of: path, at: commit, in: repository) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The viewer's rows for one file, highlighted.
    public func document(for file: FileDiff, mode: CodeDocument.Mode) async throws -> CodeDocument {
        guard !file.isBinary else { return CodeDocument(file: file, oldText: nil, newText: nil, mode: mode) }
        async let old = text(of: file, on: .base)
        async let new = text(of: file, on: .head)
        let (oldText, newText) = try await (old, new)
        // Off the caller's actor: parsing a large file takes a moment.
        return await Task.detached(priority: .userInitiated) {
            CodeDocument(file: file, oldText: oldText, newText: newText, mode: mode)
        }.value
    }
}

/// Opens a pull request: asks GitHub about it, clones or updates the
/// repository, and diffs it.
public struct ReviewLoader: Sendable {
    public enum Step: String, Sendable {
        case fetchingMetadata = "Reading the pull request"
        case cloning = "Cloning the repository"
        case fetching = "Fetching commits"
        case diffing = "Comparing"
    }

    let github: GitHubClient
    let checkouts: CheckoutStore
    let git: GitClient

    public init(github: GitHubClient, checkouts: CheckoutStore, git: GitClient) {
        self.github = github
        self.checkouts = checkouts
        self.git = git
    }

    public func load(
        _ reference: PullRequestReference,
        progress: @Sendable (Step) -> Void = { _ in }
    ) async throws -> LoadedReview {
        progress(.fetchingMetadata)
        let pullRequest = try await github.pullRequest(reference)

        if !checkouts.hasRepository(for: reference) { progress(.cloning) }
        let repository = try await checkouts.ensureRepository(for: reference)

        progress(.fetching)
        try await checkouts.fetch(pullRequest, into: repository)

        progress(.diffing)
        let mergeBase = try await git.mergeBase(pullRequest.base.sha, pullRequest.head.sha, in: repository)
        let patch = try await git.diff(from: mergeBase, to: pullRequest.head.sha, in: repository)
        let files = try UnifiedDiffParser.parse(patch)

        return LoadedReview(pullRequest: pullRequest, mergeBase: mergeBase, files: files, repository: repository, git: git)
    }
}
