import AppKit
import Foundation
import Observation
import ReviewCore
import ReviewKit

/// Top-level app state: the services, the tool check, and the pull requests
/// the reviewer has opened.
@Observable
@MainActor
final class AppModel {
    private(set) var services: AppServices?
    private(set) var toolStatuses: [ToolStatus] = []
    private(set) var isCheckingTools = false

    /// Opened pull requests, most recent first.
    private(set) var pullRequests: [PullRequestReference] = []
    var selection: PullRequestReference? {
        didSet {
            for (reference, session) in sessions { session.isSelectedInApp = reference == selection }
        }
    }
    private var sessions: [PullRequestReference: ReviewSession] = [:]
    private var startup: Task<Void, Never>?

    /// Pull requests waiting on the reviewer, from GitHub; empty until loaded.
    private(set) var inbox: [InboxItem] = []
    private(set) var isLoadingInbox = false
    private(set) var inboxError: String?

    /// Title and status of every open PR, fetched together so the sidebar can
    /// group them before each is loaded.
    private(set) var summaries: [PullRequestReference: PullRequestSummary] = [:]

    /// Asks the login shell for its environment, then checks the tools.
    /// Safe to call from several places at once: they all wait on one startup.
    func start() async {
        if startup == nil {
            startup = Task {
                let services = await AppServices.start()
                self.services = services
                restoreOpenPullRequests(from: services.workspace)
                await checkTools()
                await refresh()
            }
        }
        await startup?.value
    }

    /// Startup plus whatever the launch options ask for.
    func start(applying options: LaunchOptions) async {
        await start()
        guard let pullRequest = options.pullRequest, (try? open(pullRequest)) != nil, let selected = selectedSession else {
            if let snapshotPath = options.snapshotPath {
                try? await Task.sleep(for: .seconds(4))
                LaunchOptions.writeSnapshot(to: snapshotPath)
                NSApplication.shared.terminate(nil)
            }
            return
        }
        if let mode = options.mode { selected.mode = mode }
        if let continuous = options.continuous { selected.isContinuous = continuous }
        if !selected.hasStarted { await load(selected) }
        if let filePath = options.filePath {
            selected.selectedFilePath = filePath
            for gap in options.expandedGaps { selected.expandedGaps[filePath, default: []].insert(gap) }
        }
        if let navigation = options.navigation {
            await selected.performWhenReady(navigation.action, line: navigation.line, column: navigation.column)
        }
        if let comment = options.comment {
            await selected.scriptedComment(lines: comment.lines, note: comment.note, ask: comment.ask)
        }
        if options.opensPostSheet { selected.isPostSheetShown = true }
        if options.showsInspector { selected.isInspectorShown = true }
        if let hover = options.hover {
            await selected.performWhenReady(.definition, line: 0, column: 0, onlyWait: true)
            if let row = selected.document?.row(forNewLine: hover.line, file: selected.selectedFileIndex),
               let textView = Self.codeTextView(in: NSApp.windows.first?.contentView)
            {
                await textView.triggerHover(at: textView.rowStarts[row] + hover.column)
            }
        }
        if let snapshotPath = options.snapshotPath {
            // Let the document build and the text view lay out.
            try? await Task.sleep(for: .seconds(2))
            LaunchOptions.writeSnapshot(to: snapshotPath)
            NSApplication.shared.terminate(nil)
        }
    }

    /// The first code view in a view tree, for launch-option scripting.
    private static func codeTextView(in view: NSView?) -> CodeTextView? {
        guard let view else { return nil }
        if let found = view as? CodeTextView { return found }
        for subview in view.subviews {
            if let found = codeTextView(in: subview) { return found }
        }
        return nil
    }

    func checkTools() async {
        guard let services else { return }
        isCheckingTools = true
        toolStatuses = await services.doctor.check()
        isCheckingTools = false
    }

    var missingRequiredTools: [ToolStatus] {
        toolStatuses.filter { $0.tool.isRequired && !$0.isUsable }
    }

    /// Opens a pull request from pasted text, selecting it if already open.
    func open(_ input: String) throws(PullRequestReference.ParseError) {
        open(try PullRequestReference(parsing: input))
    }

    func open(_ reference: PullRequestReference) {
        if !pullRequests.contains(reference) {
            pullRequests.insert(reference, at: 0)
            sessions[reference] = ReviewSession(reference: reference)
            saveOpenPullRequests()
            if summaries[reference] == nil {
                Task { await refreshSummaries(of: [reference]) }
            }
        }
        selection = reference
    }

    func close(_ reference: PullRequestReference) {
        pullRequests.removeAll { $0 == reference }
        if let session = sessions.removeValue(forKey: reference) {
            Task { await session.close() }
        }
        if selection == reference { selection = pullRequests.first }
        saveOpenPullRequests()
    }

    /// Closes every open PR with this status — Merged and Closed are done with.
    func closeAll(_ status: PullRequestStatus) {
        for reference in pullRequests(with: status) { close(reference) }
    }

    /// Closes every merged and closed PR at once.
    func closeFinished() {
        for status in PullRequestStatus.allCases where status.isFinished { closeAll(status) }
    }

    // MARK: Status groups

    /// From the loaded PR when there is one, as it is the freshest; a PR whose
    /// status is not known yet counts as open.
    func status(of reference: PullRequestReference) -> PullRequestStatus {
        session(for: reference)?.review?.pullRequest.status ?? summaries[reference]?.status ?? .open
    }

    /// The open PRs in one sidebar group, in the saved order.
    func pullRequests(with status: PullRequestStatus) -> [PullRequestReference] {
        pullRequests.filter { self.status(of: $0) == status }
    }

    // MARK: Reordering the open list

    /// A drag within one status group; offsets count within the group.
    func moveOpenPullRequests(in status: PullRequestStatus, fromOffsets offsets: IndexSet, toOffset destination: Int) {
        pullRequests = ListReordering.moving(
            pullRequests, where: { self.status(of: $0) == status }, fromOffsets: offsets, toOffset: destination
        )
        saveOpenPullRequests()
    }

    /// Move Up / Move Down from a row's menu, within its group.
    func moveOpenPullRequest(_ reference: PullRequestReference, by offset: Int) {
        let status = status(of: reference)
        pullRequests = ListReordering.moving(reference, by: offset, in: pullRequests) { self.status(of: $0) == status }
        saveOpenPullRequests()
    }

    func moveOpenPullRequestToTop(_ reference: PullRequestReference) {
        moveOpenPullRequest(reference, by: -pullRequests.count)
    }

    /// The sidebar's selection changed: an inbox item is opened on selection.
    func didSelect(_ reference: PullRequestReference?) {
        guard let reference, !pullRequests.contains(reference) else { return }
        open(reference)
    }

    /// `review://open?pr=owner/repo%23123` — from `review open`, or a link.
    func handle(_ url: URL) {
        guard url.scheme == "review",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "pr" })?.value
        else { return }
        try? open(value)
    }

    /// From a notification: selects the PR, and the draft in its inspector.
    func reveal(pullRequest: String, draft: UUID?) {
        guard let reference = try? PullRequestReference(parsing: pullRequest) else { return }
        open(reference)
        guard let session = session(for: reference) else { return }
        session.isInspectorShown = true
        if let draft { session.selectedDraftID = draft }
    }

    // MARK: Open pull requests across launches

    /// Sessions are made but not loaded: each loads when it is first selected.
    private func restoreOpenPullRequests(from workspace: WorkspaceStore) {
        for reference in workspace.load() where !pullRequests.contains(reference) {
            pullRequests.append(reference)
            sessions[reference] = ReviewSession(reference: reference)
        }
        if selection == nil { selection = pullRequests.first }
        // A link that launched the app may have opened a PR before there was
        // anywhere to save it; save the merged list now.
        saveOpenPullRequests()
    }

    private func saveOpenPullRequests() {
        try? services?.workspace.save(pullRequests)
    }

    // MARK: Inbox

    /// Review requests not already open, for the sidebar's second section.
    var unopenedInbox: [InboxItem] {
        inbox.filter { !pullRequests.contains($0.reference) }
    }

    /// ⌘R: review requests, and the status of everything open.
    func refresh() async {
        async let inbox: Void = refreshInbox()
        async let summaries: Void = refreshSummaries(of: pullRequests)
        _ = await (inbox, summaries)
    }

    /// Failure leaves the last known statuses; the sidebar still works.
    private func refreshSummaries(of references: [PullRequestReference]) async {
        guard let services, !references.isEmpty,
              let fetched = try? await services.summaries(of: references)
        else { return }
        summaries.merge(fetched) { _, new in new }
    }

    func refreshInbox() async {
        guard let services, !isLoadingInbox else { return }
        isLoadingInbox = true
        defer { isLoadingInbox = false }
        do {
            inbox = try await services.inbox() ?? []
            inboxError = nil
        } catch {
            inboxError = "\(error)"
        }
    }

    var selectedSession: ReviewSession? {
        selection.flatMap(session)
    }

    /// Read-only: sessions are made by `open`, never while a view body is
    /// being evaluated, which would mutate observed state mid-update.
    func session(for reference: PullRequestReference) -> ReviewSession? {
        sessions[reference]
    }

    /// Loads (or reloads) a session. Waits for `start` if the environment is
    /// not ready yet, so a PR opened in the first half-second still loads.
    func load(_ session: ReviewSession) async {
        await start()
        guard let services, let loader = services.loader else {
            session.fail("git or gh is missing — see the tool status in the sidebar.")
            return
        }
        await session.load(with: loader, services: services)
    }
}
