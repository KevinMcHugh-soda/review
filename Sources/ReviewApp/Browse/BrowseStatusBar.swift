import SwiftUI

/// Under the browser's table: how many match, how many are shown, and Load
/// More while GitHub has further pages.
struct BrowseStatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let browser = model.browser

        HStack(spacing: Theme.tightSpacing) {
            ProgressView()
                .controlSize(.small)
                .opacity(browser.isSearching || browser.isLoadingMore ? 1 : 0)
                .accessibilityHidden(!(browser.isSearching || browser.isLoadingMore))
            Text(summary)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
            Spacer()
            if browser.hasMore {
                Button("Load More") {
                    Task { await browser.loadMore() }
                }
                .controlSize(.small)
                .disabled(browser.isLoadingMore)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.tightSpacing)
        .overlay(alignment: .top) { Divider() }
    }

    private var summary: String {
        let browser = model.browser
        guard browser.resultsQuery != nil, browser.searchError == nil else { return "" }
        if browser.listings.count < browser.totalCount {
            return "\(browser.listings.count) of \(browser.totalCount.formatted()) pull requests"
        }
        return browser.totalCount == 1 ? "1 pull request" : "\(browser.totalCount.formatted()) pull requests"
    }
}
