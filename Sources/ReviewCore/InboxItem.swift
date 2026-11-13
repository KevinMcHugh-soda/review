import Foundation

/// A pull request the reviewer has a part in, from GitHub's search.
public struct InboxItem: Hashable, Sendable, Identifiable, Codable {
    /// Why a pull request is in the inbox. One PR can have several: assigned
    /// and asked to review, say.
    public enum Reason: String, CaseIterable, Hashable, Sendable, Codable {
        /// Asked to review by name.
        case reviewRequested
        /// Asked to review through a team the reviewer is on. A PR asked of
        /// both comes back from both searches and has both reasons.
        case teamReviewRequested
        case assigned
        case authored
    }

    public let reference: PullRequestReference
    public let title: String
    public let author: String
    public let isDraft: Bool
    public let updatedAt: Date
    public var reasons: Set<Reason>
    /// Some reviewer's latest say on it is an approval. Search cannot tell,
    /// so this is filled in afterwards.
    public var isApproved: Bool

    public var id: PullRequestReference { reference }

    /// The reviewer's own pull requests go in their own section.
    public var isAuthored: Bool { reasons.contains(.authored) }

    /// The `UserDefaults` key for whether team requests wait on the reviewer.
    public static let includesTeamRequestsKey = "inboxIncludesTeamRequests"

    /// Belongs in "Waiting on You": asked by name or assigned, or — when the
    /// reviewer wants them — asked through one of their teams.
    public func isWaitingOnReviewer(includingTeamRequests: Bool) -> Bool {
        guard !isAuthored else { return false }
        return reasons.contains(.reviewRequested)
            || reasons.contains(.assigned)
            || (includingTeamRequests && reasons.contains(.teamReviewRequested))
    }

    public init(
        reference: PullRequestReference,
        title: String,
        author: String,
        isDraft: Bool,
        updatedAt: Date,
        reasons: Set<Reason> = [.reviewRequested],
        isApproved: Bool = false
    ) {
        self.reference = reference
        self.title = title
        self.author = author
        self.isDraft = isDraft
        self.updatedAt = updatedAt
        self.reasons = reasons
        self.isApproved = isApproved
    }
}

extension [InboxItem] {
    /// One item per pull request, with every reason it turned up for, newest
    /// activity first.
    public func mergingReasons() -> [InboxItem] {
        var merged: [PullRequestReference: InboxItem] = [:]
        for item in self {
            merged[item.reference, default: item].reasons.formUnion(item.reasons)
        }
        return merged.values.sorted {
            ($0.updatedAt, $1.reference.description) > ($1.updatedAt, $0.reference.description)
        }
    }
}
