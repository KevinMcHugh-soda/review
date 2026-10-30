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
    /// The base branch as fetched, which the after-merge view merges into.
    /// Can be ahead of `pullRequest.base.sha`: GitHub moves that only when
    /// the PR itself changes. The merge base stays on the API's commit, so the
    /// diff — and every line a comment is posted on — matches GitHub's.
    public let baseTip: String
    /// The changed files as the file list and the all-files view show them:
    /// in the reviewer's `fileOrder`, generated ones last.
    public private(set) var files: [FileDiff]
    /// The reviewer's order for this repository; empty leaves files as
    /// GitHub orders them.
    public private(set) var fileOrder = FileOrder()
    /// The files as git lists them, generated ones last — what `fileOrder`
    /// rearranges.
    let diffOrder: [FileDiff]
    /// Paths marked `linguist-generated` in `.gitattributes` at head or the
    /// base tip: collapsed until clicked, like GitHub.
    public let generatedPaths: Set<String>
    /// What merging into the base tip would produce, when the base has moved
    /// since the PR branched; nil when it has not, and head *is* the after-merge state.
    public let merge: GitClient.MergeResult?
    /// Set when the files are only what changed since the reviewer last
    /// viewed the PR, rather than everything the PR changes.
    public let changesSince: ChangesSince?
    /// What the files' base side is: the merge base, or for changes since
    /// last viewed, the head the reviewer saw (perhaps replayed onto the
    /// merge base). Drafts and posting still use `mergeBase`.
    let diffBase: String
    let repository: URL
    let git: GitClient

    /// Where "changes since last viewed" starts from.
    public struct ChangesSince: Hashable, Sendable {
        /// The head the reviewer last viewed.
        public let commit: String
        /// False when that head could not be replayed onto the current merge
        /// base without conflicts, so the files also carry whatever the base
        /// branch changed in them in between.
        public let isExact: Bool
    }

    init(
        pullRequest: PullRequest, mergeBase: String, baseTip: String, files: [FileDiff], generatedPaths: Set<String>,
        merge: GitClient.MergeResult?, repository: URL, git: GitClient,
        changesSince: ChangesSince? = nil, diffBase: String? = nil
    ) {
        self.pullRequest = pullRequest
        self.mergeBase = mergeBase
        self.baseTip = baseTip
        self.files = files
        diffOrder = files
        self.generatedPaths = generatedPaths
        self.merge = merge
        self.changesSince = changesSince
        self.diffBase = diffBase ?? mergeBase
        self.repository = repository
        self.git = git
    }

    /// The same review with its files in `order`. Generated files stay last.
    public func ordered(by order: FileOrder) -> Self {
        var review = self
        review.fileOrder = order
        let isGenerated = { (file: FileDiff) in generatedPaths.contains(file.path) }
        review.files = order.sorted(diffOrder.filter { !isGenerated($0) }, path: \.path)
            + order.sorted(diffOrder.filter(isGenerated), path: \.path)
        return review
    }

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
            case .base: (file.oldPath, diffBase)
            case .head: (file.newPath, pullRequest.head.sha)
            }
        guard let path, let data = try await git.contents(of: path, at: commit, in: repository) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The same PR narrowed to what changed since the reviewer saw `commit`,
    /// an earlier head — GitHub's "changes since last view".
    ///
    /// When the merge base is an ancestor of the old head, the author only
    /// added commits (or rebased without the base moving), and old head →
    /// head is exactly their change. When the base moved in between — a
    /// rebase, or the base branch merged in — that diff would also show
    /// everything the base branch did, so the old head is first replayed onto
    /// the current merge base with `git merge-tree` and the diff starts from
    /// that tree. If the replay conflicts, the plain diff is the fallback and
    /// `ChangesSince.isExact` says so.
    public func changes(since commit: String) async throws -> LoadedReview {
        let from: String
        let isExact: Bool
        if try await git.mergeBase(mergeBase, commit, in: repository) == mergeBase {
            (from, isExact) = (commit, true)
        } else if case .clean(let tree) = try await git.mergeTree(base: mergeBase, head: commit, in: repository) {
            (from, isExact) = (tree, true)
        } else {
            (from, isExact) = (commit, false)
        }
        let patch = try await git.diff(from: from, to: pullRequest.head.sha, in: repository)
        let parsed = try UnifiedDiffParser.parse(patch)
        let files = parsed.filter { !generatedPaths.contains($0.path) } + parsed.filter { generatedPaths.contains($0.path) }
        // No after-merge text: whole-file mode shows head, marked with what
        // changed since the old head.
        return LoadedReview(
            pullRequest: pullRequest, mergeBase: mergeBase, baseTip: baseTip, files: files, generatedPaths: generatedPaths,
            merge: nil, repository: repository, git: git,
            changesSince: ChangesSince(commit: commit, isExact: isExact), diffBase: from
        )
        .ordered(by: fileOrder)
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
        for file: FileDiff, mode: CodeDocument.Mode, revealed: IndexSet = []
    ) async throws -> CodeDocument {
        guard !file.isBinary else { return CodeDocument(file: file, oldText: nil, newText: nil, mode: mode) }
        async let old = text(of: file, on: .base)
        async let new = text(of: file, on: .head)
        let (oldText, newText) = try await (old, new)

        if mode == .file, let tree = mergedTree, let path = file.newPath,
           let merged = try await git.contents(of: path, at: tree, in: repository).map({ String(decoding: $0, as: UTF8.self) }),
           merged != newText
        {
            let patch = try await git.diff(from: baseTip, to: tree, paths: [path], in: repository)
            let mergeDiff = try UnifiedDiffParser.parse(patch).first ?? FileDiff(oldPath: path, newPath: path, hunks: [])
            let baseText = try await git.contents(of: path, at: baseTip, in: repository)
                .map { String(decoding: $0, as: UTF8.self) }
            return await Task.detached(priority: .userInitiated) {
                CodeDocument(file: mergeDiff, oldText: baseText, newText: merged, mode: .file).from(.afterMerge)
            }.value
        }

        // Off the caller's actor: parsing a large file takes a moment.
        return await Task.detached(priority: .userInitiated) {
            CodeDocument(file: file, oldText: oldText, newText: newText, mode: mode, revealed: revealed)
        }.value
    }

    /// Every file in one document, under a header each — the continuous view.
    ///
    /// - Parameters:
    ///   - revealed: head lines shown out of the gaps, by file path.
    ///   - collapsed: paths shown as their header only — viewed and generated
    ///     files, as on GitHub, unless the reviewer opened one again.
    ///   - viewed: paths marked viewed, for their headers.
    /// Files are read and highlighted in parallel, eight at a time: each needs
    /// two `git cat-file`s, and a large PR has hundreds.
    public func allFilesDocument(
        mode: CodeDocument.Mode,
        revealed: [String: IndexSet] = [:],
        collapsed: Set<String> = [],
        viewed: Set<String> = []
    ) async throws -> CodeDocument {
        let documents = try await withThrowingTaskGroup(of: (Int, CodeDocument?).self) { group in
            var results = [CodeDocument?](repeating: nil, count: files.count)
            var next = 0
            func addNext() {
                guard next < files.count else { return }
                let index = next
                let file = files[index]
                next += 1
                group.addTask {
                    guard !file.isBinary, !collapsed.contains(file.path) else { return (index, nil) }
                    return (index, try await document(for: file, mode: mode == .file ? .file : mode, revealed: revealed[file.path] ?? []))
                }
            }
            for _ in 0..<min(8, files.count) { addNext() }
            while let (index, document) = try await group.next() {
                results[index] = document
                addNext()
            }
            return results
        }
        let items = files.enumerated().map { index, file in
            (header: Self.header(
                for: file, isCollapsed: collapsed.contains(file.path),
                isGenerated: generatedPaths.contains(file.path), isViewed: viewed.contains(file.path)
            ), document: documents[index])
        }
        return CodeDocument(combining: items)
    }

    /// `pkg/ledger/api.go · Modified · +12 −3`, with the state that explains
    /// a header with nothing under it.
    static func header(for file: FileDiff, isCollapsed: Bool, isGenerated: Bool = false, isViewed: Bool = false) -> String {
        let status =
            switch file.status {
            case .added: "Added"
            case .deleted: "Deleted"
            case .renamed: "Renamed from \(file.oldPath ?? "")"
            case .modified: "Modified"
            }
        var parts = [file.path, status]
        if file.isBinary {
            parts.append("binary")
        } else {
            parts.append("+\(file.additions) −\(file.deletions)")
        }
        if isGenerated { parts.append("generated") }
        if isViewed { parts.append("viewed") }
        if isCollapsed { parts.append("click to show") }
        return parts.joined(separator: "  ·  ")
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

    /// - Parameter viewedHead: the head the reviewer last viewed, kept under
    ///   a ref before the fetch moves the PR's own ref past it.
    public func load(
        _ reference: PullRequestReference,
        viewedHead: String? = nil,
        progress: @Sendable (Step) -> Void = { _ in }
    ) async throws -> LoadedReview {
        progress(.fetchingMetadata)
        let pullRequest = try await github.pullRequest(reference)

        if !checkouts.hasRepository(for: reference) { progress(.cloning) }
        let repository = try await checkouts.ensureRepository(for: reference)
        if let viewedHead {
            try? await checkouts.pin(viewedHead, as: CheckoutStore.viewedRef(reference.number), in: repository)
        }

        progress(.fetching)
        try await checkouts.fetch(pullRequest, into: repository)

        progress(.diffing)
        return try await Self.review(of: pullRequest, in: repository, git: git)
    }

    /// `review` narrowed to what changed since the reviewer saw `commit`,
    /// fetching that commit first if the clone lacks it. Nil when it is gone
    /// from GitHub too.
    public func changes(in review: LoadedReview, since commit: String) async throws -> LoadedReview? {
        guard await checkouts.ensureCommit(commit, in: review.repository) else { return nil }
        try await checkouts.pin(
            commit, as: CheckoutStore.viewedRef(review.pullRequest.reference.number, isPrevious: true), in: review.repository
        )
        return try await review.changes(since: commit)
    }

    /// Everything after the fetch: the diff, which files are generated, and
    /// the merge. Separate so tests can run it on a fixture with no GitHub.
    static func review(of pullRequest: PullRequest, in repository: URL, git: GitClient) async throws -> LoadedReview {
        let mergeBase = try await git.mergeBase(pullRequest.base.sha, pullRequest.head.sha, in: repository)
        let patch = try await git.diff(from: mergeBase, to: pullRequest.head.sha, in: repository)
        let parsed = try UnifiedDiffParser.parse(patch)
        let baseTip = await git.commit(named: CheckoutStore.baseRef(pullRequest.base.name), in: repository) ?? pullRequest.base.sha
        // Best effort: a repository without attributes, or a failure reading
        // them, just means nothing is treated as generated. The base tip
        // counts too, for a rule added after the PR branched.
        let generated = (try? await git.generatedPaths(
            parsed.map(\.path), atAnyOf: [pullRequest.head.sha, baseTip], in: repository
        )) ?? []
        let files = parsed.filter { !generated.contains($0.path) } + parsed.filter { generated.contains($0.path) }
        // Only worth computing when the base has moved past the branch point.
        let merge = try await git.mergeBase(baseTip, pullRequest.head.sha, in: repository) == baseTip
            ? nil
            : try? await git.mergeTree(base: baseTip, head: pullRequest.head.sha, in: repository)

        return LoadedReview(
            pullRequest: pullRequest, mergeBase: mergeBase, baseTip: baseTip, files: files, generatedPaths: generated,
            merge: merge, repository: repository, git: git
        )
    }
}
