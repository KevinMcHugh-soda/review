import Foundation

/// A private note on some lines of code: the reviewer's own words, and any
/// conversation with Claude about them. Nothing here is on GitHub until it is
/// posted.
public struct DraftComment: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var anchor: CommentAnchor
    public var body: String
    public let createdAt: Date
    public var updatedAt: Date
    public var conversation: [ConversationTurn]
    /// The `claude -p` session the conversation lives in, for `--resume`.
    public var claudeSessionID: String?
    /// Kept private when the review is posted.
    public var isExcludedFromReview: Bool
    /// Set once the draft has gone to GitHub.
    public var posted: Posted?

    public struct Posted: Codable, Hashable, Sendable {
        public let date: Date
        /// The review it went out in.
        public let reviewURL: URL?

        public init(date: Date, reviewURL: URL?) {
            self.date = date
            self.reviewURL = reviewURL
        }
    }

    public init(anchor: CommentAnchor, body: String = "", at date: Date = .now) {
        id = UUID()
        self.anchor = anchor
        self.body = body
        createdAt = date
        updatedAt = date
        conversation = []
        isExcludedFromReview = false
    }

    // Written out so files saved before a field existed still load.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        anchor = try container.decode(CommentAnchor.self, forKey: .anchor)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        conversation = try container.decodeIfPresent([ConversationTurn].self, forKey: .conversation) ?? []
        claudeSessionID = try container.decodeIfPresent(String.self, forKey: .claudeSessionID)
        isExcludedFromReview = try container.decodeIfPresent(Bool.self, forKey: .isExcludedFromReview) ?? false
        posted = try container.decodeIfPresent(Posted.self, forKey: .posted)
    }
}

/// Which lines a draft is about.
public struct CommentAnchor: Codable, Hashable, Sendable {
    /// Relative to the checkout for files in the repository; absolute for
    /// files outside it (the Go standard library, the module cache).
    public let path: String
    public let side: Side
    /// 1-based and inclusive, numbered as on `side` at `commit`.
    public let startLine: Int
    public let endLine: Int
    /// The commit those numbers refer to: the PR's head for `.head`, the merge
    /// base for `.base`. When the PR moves on, a draft's anchor still names
    /// the code it was written about.
    public let commit: String
    /// The lines as they read when the draft was made — for the prompt, and
    /// for re-anchoring once the PR changes under the draft.
    public let quotedLines: [String]
    /// The file is one the PR changes. Only those can become line comments on
    /// GitHub.
    public let isInPullRequest: Bool

    public init(
        path: String, side: Side, startLine: Int, endLine: Int, commit: String,
        quotedLines: [String], isInPullRequest: Bool
    ) {
        self.path = path
        self.side = side
        self.startLine = startLine
        self.endLine = endLine
        self.commit = commit
        self.quotedLines = quotedLines
        self.isInPullRequest = isInPullRequest
    }

    public var lines: ClosedRange<Int> { startLine...endLine }

    /// `pkg/ledger/api.go:12–18`.
    public var description: String {
        startLine == endLine ? "\(path):\(startLine)" : "\(path):\(startLine)–\(endLine)"
    }
}

/// One message in a conversation with Claude.
public struct ConversationTurn: Codable, Hashable, Sendable, Identifiable {
    public enum Author: String, Codable, Sendable {
        case reviewer
        case claude
    }

    public let id: UUID
    public let author: Author
    public let text: String
    public let date: Date
    /// What the turn cost, as Claude Code reported it.
    public let costUSD: Double?
    /// Claude finished with an error; `text` says what went wrong.
    public let isError: Bool

    public init(author: Author, text: String, date: Date = .now, costUSD: Double? = nil, isError: Bool = false) {
        id = UUID()
        self.author = author
        self.text = text
        self.date = date
        self.costUSD = costUSD
        self.isError = isError
    }
}

/// Everything the reviewer has written on one pull request.
public struct ReviewNotes: Codable, Hashable, Sendable {
    public var drafts: [DraftComment]
    /// The "ask about all drafts" conversation.
    public var overview: [ConversationTurn]
    public var overviewSessionID: String?

    public init(drafts: [DraftComment] = [], overview: [ConversationTurn] = [], overviewSessionID: String? = nil) {
        self.drafts = drafts
        self.overview = overview
        self.overviewSessionID = overviewSessionID
    }
}
