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

    /// Asks the login shell for its environment, then checks the tools.
    /// Safe to call from several places at once: they all wait on one startup.
    func start() async {
        if startup == nil {
            startup = Task {
                let services = await AppServices.start()
                self.services = services
                restoreOpenPullRequests(from: services.workspace)
                await checkTools()
                await refreshInbox()
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
