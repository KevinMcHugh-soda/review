import Foundation
import Observation
import ReviewCore
import ReviewDiff
import ReviewKit
import ReviewLSP
import ReviewProcess

/// One open pull request: loading it, the file being looked at and how, and
/// navigating its code. Navigation lives in `ReviewSession+Navigation.swift`.
@Observable
@MainActor
final class ReviewSession {
    enum Phase {
        case loading(ReviewLoader.Step?)
        case loaded(LoadedReview)
        case failed(String)
    }

    enum DocumentState {
        case idle
        case loading
        case loaded(CodeDocument, id: String)
        case failed(String)
    }

    /// Whether ⌘-click and friends work yet. They need a checkout, which can
    /// take a while for a large repository the first time.
    enum NavigationState: Equatable {
        case preparing
        case ready
        case unavailable(String)
    }

    let reference: PullRequestReference
    private(set) var phase: Phase = .loading(nil)
    private(set) var documentState: DocumentState = .idle

    /// Whether `load` has ever run, so re-selecting the PR does not refetch.
    private(set) var hasStarted = false
    /// The changed file being shown. Picking one in the list also leaves any
    /// file that navigation had opened.
    var selectedFilePath: String? {
        didSet {
            guard selectedFilePath != oldValue else { return }
            if selectedFilePath != nil { externalFile = nil }
            // In the all-files view, picking a file scrolls to it — unless the
            // pick came from the scroll itself.
            if isContinuous, !isFollowingScroll, let path = selectedFilePath, let index = files.firstIndex(where: { $0.path == path }) {
                pendingReveal = Reveal(headerOf: index)
            }
        }
    }
    /// A file outside the PR's changes, shown because navigation landed in it.
    var externalFile: URL?
    var mode: CodeDocument.Mode = .diff
    /// Every file in one scroll, GitHub-style, rather than one at a time.
    var isContinuous = UserDefaults.standard.object(forKey: ReviewSession.continuousKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(isContinuous, forKey: Self.continuousKey) }
    }
    static let continuousKey = "showAllFilesInOneScroll"
    /// Files whose header the reviewer clicked, flipping them from collapsed
    /// (viewed or generated) to open, or open to collapsed.
    var toggledFiles: Set<String> = []
    /// Set while the file list is following the scroll, so that selecting the
    /// file being read does not scroll to it.
    var isFollowingScroll = false
    /// Gaps between hunks the reviewer has opened up, by file.
    var expandedGaps: [String: Set<Int>] = [:]

    // Navigation state; see ReviewSession+Navigation.swift.
    var navigationState: NavigationState = .preparing
    var navigator: Navigator?
    var worktree: URL?
    var serverStatus: [ServerKind: LanguageServer.Status] = [:]
    var cursor: Cursor?
    var pendingReveal: Reveal?
    var results: NavigationResults?
    /// A short note for the status strip: "No definition found".
    var navigationMessage: String?
    var backStack: [ViewerPosition] = []
    var forwardStack: [ViewerPosition] = []

    // Drafts and Claude; see ReviewSession+Drafts.swift.
    var notes = ReviewNotes()
    var notesStore: NotesStore?
    var assistant: ReviewAssistant?
    var selectedDraftID: UUID?
    var isInspectorShown = false
    /// Rows selected in the code view, for Add Comment.
    var selectedRows: ClosedRange<Int>?
    /// Follow-up questions being typed, by draft (or `overviewID`).
    var followUps: [UUID: String] = [:]
    /// Turns in flight, by draft (or `overviewID`).
    var asks: [UUID: AskProgress] = [:]
    var askTasks: [UUID: Task<Void, Never>] = [:]
    var pendingSave: Task<Void, Never>?

    // GitHub; see ReviewSession+Posting.swift.
    var publisher: ReviewPublisher?
    var threads: [ReviewThread] = []
    var threadsError: String?
    var selectedThreadID: String?
    /// Replies being typed, by thread id.
    var threadReplies: [String: String] = [:]
    var threadActions: [String: ThreadAction] = [:]
    var threadErrors: [String: String] = [:]

    enum ThreadAction {
        case replying, resolving
    }
    var isPostSheetShown = false
    /// Whether this is the PR the window shows; kept by `AppModel`.
    var isSelectedInApp = false

    /// Documents already built this session, keyed like `documentKey`.
    private var documents: [String: CodeDocument] = [:]

    init(reference: PullRequestReference) {
        self.reference = reference
    }

    var review: LoadedReview? {
        if case .loaded(let review) = phase { review } else { nil }
    }

    var files: [FileDiff] { review?.files ?? [] }

    var selectedFile: FileDiff? {
        files.first { $0.path == selectedFilePath }
    }

    var document: CodeDocument? {
        if case .loaded(let document, _) = documentState { document } else { nil }
    }

    /// Changes whenever the viewer must show something else; drives the
    /// detail column's `.task(id:)`, which cancels a superseded load.
    var documentKey: String? {
        guard review != nil else { return nil }
        if let externalFile { return "external:\(externalFile.path)" }
        guard let scrollKey else { return nil }
        if isContinuous {
            let gaps = expandedGaps.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.sorted())" }.joined(separator: ";")
            return "\(scrollKey):\(gaps):\(collapsedPaths.sorted().joined(separator: ","))"
        }
        let gaps = mode == .file ? "" : (expandedGaps[selectedFilePath ?? ""] ?? []).sorted().map(String.init).joined(separator: ",")
        return "\(scrollKey):\(gaps)"
    }

    /// Shown as their header only in the all-files view: viewed and generated
    /// files, as on GitHub — flipped for any whose header was clicked.
    var collapsedPaths: Set<String> {
        guard let review else { return [] }
        let byDefault = Set(files.filter { notes.isViewed($0, headSHA: review.pullRequest.head.sha) }.map(\.path))
            .union(review.generatedPaths)
        return byDefault.symmetricDifference(toggledFiles)
    }

    /// The file and mode being shown, without the expanded gaps: while it
    /// stays the same, the viewer keeps its scroll position.
    var scrollKey: String? {
        guard let review else { return nil }
        if let externalFile { return "external:\(externalFile.path)" }
        if isContinuous { return "all:\(review.pullRequest.head.sha):\(mode.rawValue)" }
        guard let selectedFilePath else { return nil }
        return "\(review.pullRequest.head.sha):\(selectedFilePath):\(mode.rawValue)"
    }

    /// The PR file a row of the current document belongs to: the row's own in
    /// the all-files view, else the selected file.
    func file(atRow row: Int) -> FileDiff? {
        if externalFile != nil { return nil }
        if let index = document?.file(atRow: row) { return files.indices.contains(index) ? files[index] : nil }
        return selectedFile
    }

    /// The index into `files` the all-files view uses for the selected file.
    var selectedFileIndex: Int? {
        guard isContinuous else { return nil }
        return files.firstIndex { $0.path == selectedFilePath }
    }

    func expandGap(atRow row: Int) {
        guard let document, document.rows.indices.contains(row), let gap = document.rows[row].gap,
              let path = file(atRow: row)?.path
        else { return }
        expandedGaps[path, default: []].insert(gap)
    }

    /// Clicking a file's header folds or unfolds it.
    func toggleFile(atRow row: Int) {
        guard let path = file(atRow: row)?.path else { return }
        if toggledFiles.contains(path) { toggledFiles.remove(path) } else { toggledFiles.insert(path) }
    }

    /// The file list follows whichever file is at the top of the scroll.
    func didScroll(toRow row: Int) {
        guard isContinuous, let path = file(atRow: row)?.path, path != selectedFilePath else { return }
        isFollowingScroll = true
        selectedFilePath = path
        isFollowingScroll = false
    }

    func load(with loader: ReviewLoader, services: AppServices) async {
        let environment = services.environment
        notesStore = services.notes
        assistant = services.assistant
        publisher = services.publisher
        loadNotes()
        hasStarted = true
        phase = .loading(nil)
        documents = [:]
        do {
            let review = try await loader.load(reference) { step in
                Task { @MainActor in self.didReach(step) }
            }
            phase = .loaded(review)
            if selectedFilePath == nil || selectedFile == nil {
                selectedFilePath = review.files.first?.path
            } else if isContinuous, let index = review.files.firstIndex(where: { $0.path == selectedFilePath }) {
                // A file picked while the PR was loading: scroll to it now
                // that there is somewhere to scroll.
                pendingReveal = Reveal(headerOf: index)
            }
            Task { await loadThreads() }
            await prepareNavigation(review, checkouts: loader.checkouts, environment: environment)
        } catch {
            phase = .failed("\(error)")
        }
    }

    func fail(_ message: String) {
        hasStarted = true
        phase = .failed(message)
    }

    private func didReach(_ step: ReviewLoader.Step) {
        if case .loading = phase { phase = .loading(step) }
    }

    func loadDocument() async {
        guard let review, let key = documentKey else {
            documentState = .idle
            return
        }
        cursor = nil
        selectedRows = nil
        if let cached = documents[key] {
            documentState = .loaded(cached, id: key)
            didShow(cached)
            return
        }
        documentState = .loading
        do {
            let document =
                if let externalFile { try await LoadedReview.document(forFileAt: externalFile) }
                else if isContinuous {
                    try await review.allFilesDocument(
                        mode: mode, expandedGaps: expandedGaps, collapsed: collapsedPaths,
                        viewed: Set(files.filter { isViewed($0) }.map(\.path))
                    )
                }
                else if let file = selectedFile {
                    try await review.document(for: file, mode: mode, expandedGaps: expandedGaps[file.path] ?? [])
                }
                else { CodeDocument(plainText: "", path: "") }
            guard !Task.isCancelled else { return }
            documents[key] = document
            documentState = .loaded(document, id: key)
            didShow(document)
        } catch {
            guard !Task.isCancelled else { return }
            documentState = .failed("\(error)")
        }
    }

    /// Moves the selection by `offset` files, stopping at either end.
    func selectFile(offset: Int) {
        guard let index = files.firstIndex(where: { $0.path == selectedFilePath }) else {
            selectedFilePath = files.first?.path
            return
        }
        let target = min(max(index + offset, 0), files.count - 1)
        selectedFilePath = files[target].path
    }

    func close() async {
        for task in askTasks.values { task.cancel() }
        saveNotesNow()
        await navigator?.shutdown()
        navigator = nil
    }
}
