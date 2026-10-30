import Foundation

/// Where the browser searches: one repository, every tracked one, or
/// anywhere the reviewer is involved.
public enum BrowseScope: Hashable, Sendable, Codable {
    case involvingMe
    case tracked
    case repository(RepositoryName)

    /// The scope's search qualifiers. Tracked with nothing tracked falls back
    /// to involving the reviewer: a search of all of GitHub is never useful.
    public func qualifiers(tracked: [RepositoryName]) -> [String] {
        switch self {
        case .involvingMe:
            ["involves:@me"]
        case .tracked:
            tracked.isEmpty ? ["involves:@me"] : tracked.map { "repo:\($0)" }
        case .repository(let repository):
            ["repo:\(repository)"]
        }
    }

    public var title: String {
        switch self {
        case .involvingMe: "Involving You"
        case .tracked: "Tracked Repositories"
        case .repository(let repository): repository.description
        }
    }

    /// Results from one repository need not repeat its name on every row.
    public var spansRepositories: Bool {
        switch self {
        case .involvingMe, .tracked: true
        case .repository: false
        }
    }
}
