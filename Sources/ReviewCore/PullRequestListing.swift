import Foundation

/// A pull request as the browser lists it: enough to choose one to open.
public struct PullRequestListing: Hashable, Sendable, Identifiable {
    /// Where the reviews stand. GitHub's own decision where the repository
    /// requires reviews, otherwise read from each reviewer's latest say.
    public enum ReviewState: String, Hashable, Sendable {
        case approved, changesRequested, reviewRequired

        public var title: String {
            switch self {
            case .approved: "Approved"
            case .changesRequested: "Changes requested"
            case .reviewRequired: "Review required"
            }
        }
    }

    public let reference: PullRequestReference
    public let title: String
    public let author: String
    public let status: PullRequestStatus
    public let createdAt: Date
    public let updatedAt: Date
    public let additions: Int
    public let deletions: Int
    public let reviewState: ReviewState?
    /// The head commit, so a size counted for it is known to be current.
    public let headSHA: String?

    public var id: PullRequestReference { reference }

    public init(
        reference: PullRequestReference,
        title: String,
        author: String,
        status: PullRequestStatus,
        createdAt: Date,
        updatedAt: Date,
        additions: Int = 0,
        deletions: Int = 0,
        reviewState: ReviewState? = nil,
        headSHA: String? = nil
    ) {
        self.reference = reference
        self.title = title
        self.author = author
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.additions = additions
        self.deletions = deletions
        self.reviewState = reviewState
        self.headSHA = headSHA
    }
}

/// One page of search results, and how to ask for the next.
public struct PullRequestSearchPage: Sendable {
    public let listings: [PullRequestListing]
    /// Every match, not just this page's; GitHub stops returning pages after
    /// a thousand.
    public let totalCount: Int
    /// Pass to the next search for the page after this one; nil on the last.
    public let nextCursor: String?

    public init(listings: [PullRequestListing], totalCount: Int, nextCursor: String?) {
        self.listings = listings
        self.totalCount = totalCount
        self.nextCursor = nextCursor
    }
}
