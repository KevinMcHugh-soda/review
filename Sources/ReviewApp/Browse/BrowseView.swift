import ReviewCore
import SwiftUI

/// The browser's detail column: filters across the top, matching pull
/// requests in a table, a count and Load More along the bottom. Searching is
/// keyed on the query, so any change — a word, a filter, the scope — searches
/// again, and one typed in quick succession cancels the search before it.
struct BrowseView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var browser = model.browser
        let query = browser.query(tracked: model.trackedRepositories)

        // Stacked rather than safe-area insets: the table's scroll view does
        // not leave room for an inset, and its rows showed through the bars.
        VStack(spacing: 0) {
            BrowseFilterBar()
            BrowseTable()
                .overlay { emptyState }
            BrowseStatusBar()
        }
        .searchable(text: $browser.filter.keywords, placement: .toolbar, prompt: "Search titles")
        .task(id: query) {
            // Typing waits for a pause; the first search on showing does not.
            if browser.resultsQuery != nil {
                try? await Task.sleep(for: Theme.searchDelay)
                guard !Task.isCancelled else { return }
            }
            await browser.search(query)
            await browser.countLines()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let browser = model.browser
        if browser.listings.isEmpty {
            if let error = browser.searchError {
                ContentUnavailableView {
                    Label("Couldn't Search", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") {
                        Task { await browser.search(browser.query(tracked: model.trackedRepositories)) }
                    }
                }
            } else if browser.isSearching || browser.resultsQuery == nil {
                ProgressView()
            } else if !browser.filter.keywords.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: browser.filter.keywords)
            } else {
                ContentUnavailableView {
                    Label("No Pull Requests", systemImage: "tray")
                } description: {
                    Text("Nothing in \(browser.scope.title) matches these filters.")
                } actions: {
                    if browser.filter.hasConditions {
                        Button("Clear Filters") { browser.clearConditions() }
                    }
                }
            }
        }
    }
}
