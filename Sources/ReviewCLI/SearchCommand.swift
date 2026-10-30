import ArgumentParser
import Foundation
import ReviewCore
import ReviewKit

/// Searches pull requests exactly as the app's browser does and prints them,
/// with the query it sent.
struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search pull requests by title and filters, as the browser does.",
        discussion: "Logins may be @me. Without --repo, searches the tracked repositories, or everything involving you."
    )

    @Argument(help: "Words to find in titles.")
    var keywords: [String] = []

    @Option(help: "Search this repository (owner/repo) only.")
    var repo: String?

    @Flag(help: "Search everything involving you instead of the tracked repositories.")
    var involvingMe = false

    @Option(help: "open, merged, closed or all.")
    var state = PullRequestFilter.State.open

    @Option(help: "any, draft or ready.")
    var drafts = PullRequestFilter.Readiness.any

    @Option(help: "any, none, required, approved or changesRequested.")
    var review = PullRequestFilter.Review.any

    @Option(help: "Written by this login (repeatable).")
    var author: [String] = []

    @Option(help: "Not written by this login (repeatable).")
    var notAuthor: [String] = []

    @Option(help: "Reviewed by this login (repeatable).")
    var reviewedBy: [String] = []

    @Option(help: "Review requested from this login or org/team (repeatable).")
    var reviewRequested: [String] = []

    @Flag(help: "Fetch the next page too.")
    var more = false

    func run() async throws {
        let services = await AppServices.start()
        let scope: BrowseScope = if let repo {
            .repository(try RepositoryName(parsing: repo))
        } else if involvingMe {
            .involvingMe
        } else {
            .tracked
        }
        let people = author.map { PersonCondition(role: .author, login: $0) }
            + notAuthor.map { PersonCondition(role: .author, login: $0, isExcluded: true) }
            + reviewedBy.map { PersonCondition(role: .reviewedBy, login: $0) }
            + reviewRequested.map { PersonCondition(role: .reviewRequested, login: $0) }
        for person in people where !person.isValid {
            throw ValidationError("\(person.login) is not a login.")
        }
        let filter = PullRequestFilter(
            keywords: keywords.joined(separator: " "), state: state, readiness: drafts, review: review, people: people
        )
        let query = filter.searchQuery(scope: scope.qualifiers(tracked: services.trackedRepositories.load()))
        print("query: \(query)")

        guard var page = try await services.searchPullRequests(query) else {
            throw ValidationError("gh is missing — run `review doctor`.")
        }
        var listings = page.listings
        if more, let cursor = page.nextCursor, let next = try await services.searchPullRequests(query, after: cursor) {
            page = next
            listings += next.listings
        }
        print("\(page.totalCount) pull requests\n")
        let sizes = (try? await services.reviewSizes(of: listings.map(\.reference), attributes: [:]))??.sizes ?? [:]
        for listing in listings {
            var tags = [listing.status == .open ? nil : listing.status.title.lowercased(), listing.reviewState?.title.lowercased()]
                .compactMap(\.self)
            if let size = sizes[listing.reference] {
                let lines = size[.implementation]
                tags.append("implementation +\(lines.additions) −\(lines.deletions) of +\(listing.additions) −\(listing.deletions)")
            } else {
                tags.append("+\(listing.additions) −\(listing.deletions)")
            }
            print("\(listing.reference)  \(listing.title)")
            print("    \(listing.author) · updated \(listing.updatedAt.formatted(.relative(presentation: .named))) · \(tags.joined(separator: " · "))")
        }
        if page.nextCursor != nil {
            print("\n… more on the next page")
        }
    }
}

extension PullRequestFilter.State: ExpressibleByArgument {}
extension PullRequestFilter.Readiness: ExpressibleByArgument {}
extension PullRequestFilter.Review: ExpressibleByArgument {}
