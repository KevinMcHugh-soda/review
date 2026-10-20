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
    var selection: PullRequestReference?
    private var sessions: [PullRequestReference: ReviewSession] = [:]
    private var startup: Task<Void, Never>?

    /// Asks the login shell for its environment, then checks the tools.
    /// Safe to call from several places at once: they all wait on one startup.
    func start() async {
        if startup == nil {
            startup = Task {
                services = await AppServices.start()
                await checkTools()
            }
        }
        await startup?.value
    }

    /// Startup plus whatever the launch options ask for.
    func start(applying options: LaunchOptions) async {
        await start()
        guard let pullRequest = options.pullRequest, (try? open(pullRequest)) != nil, let selected = selectedSession else {
            return
        }
        if options.wholeFile { selected.mode = .file }
        if !selected.hasStarted { await load(selected) }
        if let filePath = options.filePath { selected.selectedFilePath = filePath }
        if let navigation = options.navigation {
            await selected.performWhenReady(navigation.action, line: navigation.line, column: navigation.column)
        }
        if let comment = options.comment {
            await selected.scriptedComment(lines: comment.lines, note: comment.note, ask: comment.ask)
        }
        if options.opensPostSheet { selected.isPostSheetShown = true }
        if let snapshotPath = options.snapshotPath {
            // Let the document build and the text view lay out.
            try? await Task.sleep(for: .seconds(2))
            LaunchOptions.writeSnapshot(to: snapshotPath)
            NSApplication.shared.terminate(nil)
        }
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
        let reference = try PullRequestReference(parsing: input)
        if !pullRequests.contains(reference) {
            pullRequests.insert(reference, at: 0)
            sessions[reference] = ReviewSession(reference: reference)
        }
        selection = reference
    }

    func close(_ reference: PullRequestReference) {
        pullRequests.removeAll { $0 == reference }
        if let session = sessions.removeValue(forKey: reference) {
            Task { await session.close() }
        }
        if selection == reference { selection = pullRequests.first }
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
