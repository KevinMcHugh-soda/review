import Foundation

/// Where a pull request stands, as the sidebar groups it: a draft is open but
/// not ready, so it gets its own group.
public enum PullRequestStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case open, draft, merged, closed

    public var title: String {
        switch self {
        case .open: "Open"
        case .draft: "Draft"
        case .merged: "Merged"
        case .closed: "Closed"
        }
    }

    /// Merged and closed pull requests are done with; the sidebar offers to
    /// close them all.
    public var isFinished: Bool {
        switch self {
        case .open, .draft: false
        case .merged, .closed: true
        }
    }
}

/// A pull request's title and status, fetched for every open PR at once so
/// the sidebar can group them before any is loaded.
public struct PullRequestSummary: Hashable, Sendable, Codable {
    public let reference: PullRequestReference
    public let title: String
    public let status: PullRequestStatus

    public init(reference: PullRequestReference, title: String, status: PullRequestStatus) {
        self.reference = reference
        self.title = title
        self.status = status
    }
}

extension PullRequest {
    public var status: PullRequestStatus {
        switch state {
        case .open: isDraft ? .draft : .open
        case .closed: .closed
        case .merged: .merged
        }
    }
}
