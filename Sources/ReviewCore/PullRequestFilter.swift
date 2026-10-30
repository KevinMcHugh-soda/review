import Foundation

/// What the browser looks for: words in the title, plus the conditions
/// GitHub's pull request search understands. Turned into one search query by
/// `searchQuery(scope:)`.
public struct PullRequestFilter: Hashable, Sendable, Codable {
    public enum State: String, CaseIterable, Hashable, Sendable, Codable {
        case open, merged, closed, all

        public var title: String {
            switch self {
            case .open: "Open"
            case .merged: "Merged"
            case .closed: "Closed"
            case .all: "Any State"
            }
        }
    }

    public enum Readiness: String, CaseIterable, Hashable, Sendable, Codable {
        case any, draft, ready

        public var title: String {
            switch self {
            case .any: "Drafts and Ready"
            case .draft: "Drafts"
            case .ready: "Ready for Review"
            }
        }
    }

    /// GitHub's `review:` qualifier.
    public enum Review: String, CaseIterable, Hashable, Sendable, Codable {
        case any, none, required, approved, changesRequested

        public var title: String {
            switch self {
            case .any: "Any Review"
            case .none: "Not Reviewed"
            case .required: "Review Required"
            case .approved: "Approved"
            case .changesRequested: "Changes Requested"
            }
        }
    }

    public enum Sort: String, CaseIterable, Hashable, Sendable, Codable {
        case recentlyUpdated, newest, oldest, leastRecentlyUpdated

        public var title: String {
            switch self {
            case .recentlyUpdated: "Recently Updated"
            case .newest: "Newest"
            case .oldest: "Oldest"
            case .leastRecentlyUpdated: "Least Recently Updated"
            }
        }
    }

    /// Words matched against titles. Typed GitHub qualifiers (`label:bug`)
    /// pass through as they are.
    public var keywords: String
    public var state: State
    public var readiness: Readiness
    public var review: Review
    public var people: [PersonCondition]
    public var sort: Sort

    public init(
        keywords: String = "",
        state: State = .open,
        readiness: Readiness = .any,
        review: Review = .any,
        people: [PersonCondition] = [],
        sort: Sort = .recentlyUpdated
    ) {
        self.keywords = keywords
        self.state = state
        self.readiness = readiness
        self.review = review
        self.people = people
        self.sort = sort
    }

    /// Everything but the keywords and the sort is at its default.
    public var hasConditions: Bool {
        var conditions = self
        conditions.keywords = ""
        conditions.sort = .recentlyUpdated
        return conditions != Self()
    }

    /// The query for GitHub's search, `is:pr` first. People whose login is
    /// not a login yet — half typed, say — are left out rather than sent.
    public func searchQuery(scope: [String]) -> String {
        let keywords = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = ["is:pr"] + scope + stateQualifiers + readinessQualifiers + reviewQualifiers
            + people.compactMap(\.qualifier) + [sortQualifier]
            + (keywords.isEmpty ? [] : ["in:title", keywords])
        return terms.joined(separator: " ")
    }

    private var stateQualifiers: [String] {
        switch state {
        case .open: ["is:open"]
        case .merged: ["is:merged"]
        // `is:closed` alone includes merged pull requests.
        case .closed: ["is:closed", "is:unmerged"]
        case .all: []
        }
    }

    private var readinessQualifiers: [String] {
        switch readiness {
        case .any: []
        case .draft: ["draft:true"]
        case .ready: ["draft:false"]
        }
    }

    private var reviewQualifiers: [String] {
        switch review {
        case .any: []
        case .none: ["review:none"]
        case .required: ["review:required"]
        case .approved: ["review:approved"]
        case .changesRequested: ["review:changes_requested"]
        }
    }

    private var sortQualifier: String {
        switch sort {
        case .recentlyUpdated: "sort:updated-desc"
        case .newest: "sort:created-desc"
        case .oldest: "sort:created-asc"
        case .leastRecentlyUpdated: "sort:updated-asc"
        }
    }
}

/// One condition on a person: "author is not @me", "reviewed by kevin".
public struct PersonCondition: Hashable, Sendable, Codable, Identifiable {
    public enum Role: String, CaseIterable, Hashable, Sendable, Codable {
        case author, reviewedBy, reviewRequested, assignee, involves

        /// The search qualifier, without its colon.
        var qualifier: String {
            switch self {
            case .author: "author"
            case .reviewedBy: "reviewed-by"
            case .reviewRequested: "review-requested"
            case .assignee: "assignee"
            case .involves: "involves"
            }
        }

        public func title(isExcluded: Bool) -> String {
            switch self {
            case .author: isExcluded ? "Author Is Not" : "Author"
            case .reviewedBy: isExcluded ? "Not Reviewed By" : "Reviewed By"
            case .reviewRequested: isExcluded ? "Review Not Requested From" : "Review Requested From"
            case .assignee: isExcluded ? "Not Assigned To" : "Assigned To"
            case .involves: isExcluded ? "Doesn't Involve" : "Involves"
            }
        }
    }

    /// A role and whether it is negated: what the token's menu picks.
    public struct Sense: Hashable, Sendable, CaseIterable {
        public let role: Role
        public let isExcluded: Bool

        public init(role: Role, isExcluded: Bool) {
            self.role = role
            self.isExcluded = isExcluded
        }

        public static var allCases: [Self] {
            Role.allCases.flatMap { [Self(role: $0, isExcluded: false), Self(role: $0, isExcluded: true)] }
        }

        public var title: String { role.title(isExcluded: isExcluded) }
    }

    public let id: UUID
    public var role: Role
    public var login: String
    public var isExcluded: Bool

    public var sense: Sense {
        get { Sense(role: role, isExcluded: isExcluded) }
        set {
            role = newValue.role
            isExcluded = newValue.isExcluded
        }
    }

    public init(id: UUID = UUID(), role: Role, login: String = "", isExcluded: Bool = false) {
        self.id = id
        self.role = role
        self.login = login
        self.isExcluded = isExcluded
    }

    /// `author:dev`, `-reviewed-by:@me`; nil while the login is not one.
    public var qualifier: String? {
        guard let login = Self.normalized(login) else { return nil }
        return "\(isExcluded ? "-" : "")\(role.qualifier):\(login)"
    }

    /// Typed with nothing in it yet; not worth flagging as wrong.
    public var isBlank: Bool { login.trimmingCharacters(in: .whitespaces).isEmpty }

    public var isValid: Bool { Self.normalized(login) != nil }

    /// `@me`, a login (`@kevin` loses its `@`), `app/dependabot` for an app,
    /// or `org/team` for a team asked to review. Nil for anything else, which
    /// would otherwise change the meaning of the whole query.
    static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "@me" { return "@me" }
        let login = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let parts = login.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy(isNamePart),
              parts[0].first != "-"
        else { return nil }
        return login
    }

    private static func isNamePart(_ part: Substring) -> Bool {
        !part.isEmpty && part.count <= 100 && part.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".")
        }
    }
}
