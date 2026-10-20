import Foundation
import Observation
import ReviewCore
import ReviewKit

/// Top-level app state. For now: the services, the tool check, and the pull
/// requests the reviewer has opened.
@Observable
@MainActor
final class AppModel {
    private(set) var services: AppServices?
    private(set) var toolStatuses: [ToolStatus] = []
    private(set) var isCheckingTools = false

    /// Opened pull requests, most recent first.
    private(set) var pullRequests: [PullRequestReference] = []
    var selection: PullRequestReference?

    /// Asks the login shell for its environment, then checks the tools.
    /// Called once from the window's `.task`.
    func start() async {
        guard services == nil else { return }
        services = await AppServices.start()
        await checkTools()
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
        }
        selection = reference
    }
}
