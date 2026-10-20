import Foundation

/// What GitHub says about a pull request — enough to check it out and to
/// head the review.
public struct PullRequest: Hashable, Sendable, Codable {
    public let reference: PullRequestReference
    public let title: String
    /// The description, in GitHub-flavoured Markdown. Empty when the author
    /// wrote none.
    public let body: String
    public let author: String
    public let state: State
    public let isDraft: Bool
    public let base: Branch
    public let head: Branch

    public enum State: String, Hashable, Sendable, Codable {
        case open, closed, merged
    }

    /// One end of the pull request: a branch name and the commit it pointed
    /// at when this was fetched.
    public struct Branch: Hashable, Sendable, Codable {
        public let name: String
        public let sha: String

        public init(name: String, sha: String) {
            self.name = name
            self.sha = sha
        }
    }

    public init(
        reference: PullRequestReference,
        title: String,
        body: String,
        author: String,
        state: State,
        isDraft: Bool,
        base: Branch,
        head: Branch
    ) {
        self.reference = reference
        self.title = title
        self.body = body
        self.author = author
        self.state = state
        self.isDraft = isDraft
        self.base = base
        self.head = head
    }
}
