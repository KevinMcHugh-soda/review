import Foundation

/// A pull request waiting on the reviewer, from GitHub's search.
public struct InboxItem: Hashable, Sendable, Identifiable, Codable {
    public let reference: PullRequestReference
    public let title: String
    public let author: String
    public let isDraft: Bool
    public let updatedAt: Date

    public var id: PullRequestReference { reference }

    public init(reference: PullRequestReference, title: String, author: String, isDraft: Bool, updatedAt: Date) {
        self.reference = reference
        self.title = title
        self.author = author
        self.isDraft = isDraft
        self.updatedAt = updatedAt
    }
}
