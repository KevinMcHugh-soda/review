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
    /// What merging would produce, when the base has moved since the PR
    /// branched; nil when it has not, and head *is* the after-merge state.
    public let merge: GitClient.MergeResult?
    let repository: URL
    let git: GitClient

    /// The base has moved and merging is clean, so whole-file views can show
    /// the real after-merge text.
    var mergedTree: String? {
        if case .clean(let tree) = merge { tree } else { nil }
    }

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

    /// A checkout of head for the language servers. Slow the first time for a
    /// large repository — a blobless clone fetches every file at head now.
    public func checkOut(using checkouts: CheckoutStore) async throws -> URL {
        try await checkouts.ensureWorktree(for: pullRequest, repository: repository)
    }

    /// The viewer's rows for one file, highlighted.
    ///
    /// Whole-file mode shows the file as it will be after the merge. When the
    /// base has moved and changed this file too, that differs from head: the
    /// text comes from the merge tree and the marks from diffing the base tip
    /// against it — what the merge adds, in the merged file's numbering.
    public func document(
        for file: FileDiff, mode: CodeDocument.Mode, expandedGaps: Set<Int> = []
    ) async throws -> CodeDocument {
        guard !file.isBinary else { return CodeDocument(file: file, oldText: nil, newText: nil, mode: mode) }
        async let old = text(of: file, on: .base)
        async let new = text(of: file, on: .head)
        let (oldText, newText) = try await (old, new)

        if mode == .file, let tree = mergedTree, let path = file.newPath,
           let merged = try await git.contents(of: path, at: tree, in: repository).map({ String(decoding: $0, as: UTF8.self) }),
           merged != newText
        {
            let patch = try await git.diff(from: pullRequest.base.sha, to: tree, paths: [path], in: repository)
            let mergeDiff = try UnifiedDiffParser.parse(patch).first ?? FileDiff(oldPath: path, newPath: path, hunks: [])
            let baseText = try await git.contents(of: path, at: pullRequest.base.sha, in: repository)
                .map { String(decoding: $0, as: UTF8.self) }
            return await Task.detached(priority: .userInitiated) {
                CodeDocument(file: mergeDiff, oldText: baseText, newText: merged, mode: .file).from(.afterMerge)
            }.value
        }

        // Off the caller's actor: parsing a large file takes a moment.
        return await Task.detached(priority: .userInitiated) {
            CodeDocument(file: file, oldText: oldText, newText: newText, mode: mode, expandedGaps: expandedGaps)
        }.value
    }

    /// Any file on disk, for a definition outside the PR's changes.
    public static func document(forFileAt url: URL) async throws -> CodeDocument {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            return CodeDocument(plainText: String(decoding: data, as: UTF8.self), path: url.path)
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
    public let checkouts: CheckoutStore
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
        // Only worth computing when the base has moved past the branch point.
        let merge = mergeBase == pullRequest.base.sha
            ? nil
            : try? await git.mergeTree(base: pullRequest.base.sha, head: pullRequest.head.sha, in: repository)

        return LoadedReview(
            pullRequest: pullRequest, mergeBase: mergeBase, files: files, merge: merge,
            repository: repository, git: git
        )
    }
}
