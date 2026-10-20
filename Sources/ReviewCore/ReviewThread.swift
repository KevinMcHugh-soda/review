import Foundation

/// A conversation already on GitHub, anchored to lines of the diff.
public struct ReviewThread: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public let path: String
    public let side: Side
    /// Where the thread sits in the current diff; nil once outdated.
    public let line: Int?
    public let startLine: Int?
    /// Where it was written, which outlives the line moving.
    public let originalLine: Int?
    public let isResolved: Bool
    public let isOutdated: Bool
    public let comments: [ThreadComment]

    public init(
        id: String, path: String, side: Side, line: Int?, startLine: Int?, originalLine: Int?,
        isResolved: Bool, isOutdated: Bool, comments: [ThreadComment]
    ) {
        self.id = id
        self.path = path
        self.side = side
        self.line = line
        self.startLine = startLine
        self.originalLine = originalLine
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.comments = comments
    }

    /// The lines the thread covers now, if it is not outdated.
    public var lines: ClosedRange<Int>? {
        guard let line else { return nil }
        return (startLine ?? line)...line
    }
}

public struct ThreadComment: Hashable, Sendable, Codable, Identifiable {
    public let author: String
    public let body: String
    public let createdAt: Date
    public let url: URL?

    public var id: String { url?.absoluteString ?? "\(author)-\(createdAt.timeIntervalSince1970)" }

    public init(author: String, body: String, createdAt: Date, url: URL?) {
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.url = url
    }
}

/// How a review is submitted.
public enum ReviewEvent: String, CaseIterable, Sendable, Codable {
    case comment = "COMMENT"
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
    /// Created but not submitted: it waits on GitHub, visible only to the
    /// reviewer, to be finished there.
    case pending = "PENDING"

    public var title: String {
        switch self {
        case .comment: "Comment"
        case .approve: "Approve"
        case .requestChanges: "Request Changes"
        case .pending: "Leave Pending on GitHub"
        }
    }

    /// GitHub refuses approving or requesting changes on your own PR.
    public var isAllowedOnOwnPullRequest: Bool {
        switch self {
        case .comment, .pending: true
        case .approve, .requestChanges: false
        }
    }
}
