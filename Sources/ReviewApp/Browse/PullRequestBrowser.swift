import Foundation
import Observation
import ReviewCore
import ReviewKit

/// The browser's state: where it searches, the filter, and the results of
/// the last search. Searches are driven by the view (`search(_:)` from a
/// task keyed on the query), so a change in quick succession cancels the
/// search before it.
@Observable
@MainActor
final class PullRequestBrowser {
    var scope = BrowseScope.involvingMe {
        didSet { save() }
    }
    var filter = PullRequestFilter() {
        didSet { save() }
    }

    private(set) var listings: [PullRequestListing] = []
    private(set) var totalCount = 0
    /// The query `listings` answer; a page for another query is dropped.
    private(set) var resultsQuery: String?
    private var nextCursor: String?
    private(set) var isSearching = false
    private(set) var isLoadingMore = false
    private(set) var searchError: String?

    /// Line counts by category, for the head commit they were counted at;
    /// see `size(of:)`.
    private(set) var sizes: [PullRequestReference: CountedSize] = [:]
    private var counting: Set<PullRequestReference> = []
    /// Each repository's `.gitattributes`, read once per session (and again
    /// on Refresh), for telling generated files apart.
    private var attributes: [RepositoryName: GitAttributes] = [:]

    struct CountedSize {
        let headSHA: String?
        let size: ReviewSize
    }

    /// Every repository the reviewer can see, most recently pushed first.
    private(set) var repositories: [RepositoryName] = []
    private(set) var isLoadingRepositories = false
    private(set) var repositoriesError: String?

    private var services: AppServices?
    private var isRestoring = false
    /// The query being searched for; a cancelled search that finishes late
    /// must not clear the spinner of the one that replaced it.
    private var pendingQuery: String?

    /// Restores the last scope and filter. With none saved, the tracked
    /// repositories when there are any, otherwise everything involving the
    /// reviewer.
    func start(with services: AppServices, tracked: [RepositoryName]) {
        self.services = services
        let saved = services.browse.load()
        isRestoring = true
        scope = saved.scope ?? (tracked.isEmpty ? .involvingMe : .tracked)
        filter = saved.filter
        isRestoring = false
    }

    /// Tracked Repositories has nothing to show once nothing is tracked.
    func didChangeTrackedRepositories(_ tracked: [RepositoryName]) {
        if tracked.isEmpty, scope == .tracked { scope = .involvingMe }
    }

    func query(tracked: [RepositoryName]) -> String {
        filter.searchQuery(scope: scope.qualifiers(tracked: tracked))
    }

    var hasMore: Bool { nextCursor != nil }

    /// The first page for `query`. Results for the previous query stay up
    /// while it runs, so the table does not flash empty.
    func search(_ query: String) async {
        guard let services else { return }
        pendingQuery = query
        isSearching = true
        defer {
            if pendingQuery == query { isSearching = false }
        }
        do {
            let page = try await services.searchPullRequests(query)
            guard !Task.isCancelled else { return }
            listings = page?.listings ?? []
            totalCount = page?.totalCount ?? 0
            nextCursor = page?.nextCursor
            resultsQuery = query
            searchError = page == nil ? "gh is missing — see the tool status in the sidebar." : nil
        } catch {
            guard !Task.isCancelled else { return }
            listings = []
            totalCount = 0
            nextCursor = nil
            resultsQuery = query
            searchError = "\(error)"
        }
    }

    /// The next page, when the last row comes into view.
    func loadMore() async {
        guard let services, let query = resultsQuery, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await services.searchPullRequests(query, after: cursor), resultsQuery == query else { return }
        let known = Set(listings.map(\.reference))
        listings += page.listings.filter { !known.contains($0.reference) }
        nextCursor = page.nextCursor
        isLoadingMore = false
        await countLines()
    }

    var isCounting: Bool { !counting.isEmpty }

    /// Nil until counted, and again once the pull request has a new head.
    func size(of listing: PullRequestListing) -> ReviewSize? {
        sizes[listing.reference].flatMap { $0.headSHA == listing.headSHA ? $0.size : nil }
    }

    /// Splits each listed pull request's lines into implementation,
    /// generated, tests and documentation — GitHub's own totals count
    /// generated output, which for one OpenAPI or sqlc change is most of the
    /// diff. Failure leaves those rows showing GitHub's totals.
    func countLines() async {
        guard let services else { return }
        let needed = listings.filter { size(of: $0) == nil && !counting.contains($0.reference) }
        guard !needed.isEmpty else { return }
        counting.formUnion(needed.map(\.reference))
        defer { counting.subtract(needed.map(\.reference)) }
        guard let counted = try? await services.reviewSizes(of: needed.map(\.reference), attributes: attributes) else { return }
        attributes = counted.attributes
        for listing in needed {
            guard let size = counted.sizes[listing.reference] else { continue }
            sizes[listing.reference] = CountedSize(headSHA: listing.headSHA, size: size)
        }
    }

    /// A repository's generated-file rules may have changed since.
    func forgetAttributes() {
        attributes = [:]
        sizes = [:]
    }

    /// Fetched once, when the browser is first shown, and again on Refresh.
    func loadRepositories(force: Bool = false) async {
        guard let services, !isLoadingRepositories, force || repositories.isEmpty else { return }
        isLoadingRepositories = true
        defer { isLoadingRepositories = false }
        do {
            repositories = try await services.repositories() ?? []
            repositoriesError = nil
        } catch {
            repositoriesError = "\(error)"
        }
    }

    /// Back to the defaults; the words stay, as they are in the search field.
    func clearConditions() {
        filter = PullRequestFilter(keywords: filter.keywords, sort: filter.sort)
    }

    func addPerson(_ role: PersonCondition.Role, isExcluded: Bool = false, login: String = "") -> PersonCondition.ID {
        let person = PersonCondition(role: role, login: login, isExcluded: isExcluded)
        filter.people.append(person)
        return person.id
    }

    func removePerson(_ id: PersonCondition.ID) {
        filter.people.removeAll { $0.id == id }
    }

    private func save() {
        guard !isRestoring else { return }
        try? services?.browse.save(BrowseStore.Saved(scope: scope, filter: filter))
    }
}
