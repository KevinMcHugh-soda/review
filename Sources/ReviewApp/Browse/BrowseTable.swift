import AppKit
import ReviewCore
import SwiftUI

/// The matching pull requests. Double-click or Return opens the selection in
/// the sidebar; the last row coming into view fetches the next page.
struct BrowseTable: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<PullRequestReference> = []

    var body: some View {
        let browser = model.browser
        let spansRepositories = browser.scope.spansRepositories

        Table(browser.listings, selection: $selection) {
            TableColumn("Title") { listing in
                BrowseTitleCell(listing: listing, isInSidebar: model.pullRequests.contains(listing.reference))
                    .task {
                        if listing.id == browser.listings.last?.id { await browser.loadMore() }
                    }
            }
            .width(min: Theme.browseTitleMinWidth, ideal: Theme.browseTitleIdealWidth)
            TableColumn("Number") { listing in
                // Verbatim: a localized number would be "#15,303".
                Text(verbatim: spansRepositories ? "\(listing.reference.repository)#\(listing.reference.number)" : "#\(listing.reference.number)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help(listing.reference.description)
            }
            .width(min: Theme.browseNarrowColumnWidth, ideal: spansRepositories ? Theme.browseWideColumnWidth : Theme.browseNarrowColumnWidth)
            TableColumn("Author") { listing in
                Text(listing.author)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: Theme.browseNarrowColumnWidth, ideal: Theme.browseWideColumnWidth)
            TableColumn("Review") { listing in
                ReviewStateLabel(state: listing.reviewState)
            }
            .width(min: Theme.browseNarrowColumnWidth, ideal: Theme.browseWideColumnWidth)
            TableColumn("Implementation") { listing in
                BrowseSizeCell(listing: listing, size: browser.size(of: listing))
            }
            .width(min: Theme.browseNarrowColumnWidth, ideal: Theme.browseWideColumnWidth)
            TableColumn("Updated") { listing in
                Text(listing.updatedAt, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
                    .help(listing.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .width(min: Theme.browseNarrowColumnWidth, ideal: Theme.browseNarrowColumnWidth)
        }
        .contextMenu(forSelectionType: PullRequestReference.self) { references in
            menu(for: references)
        } primaryAction: { references in
            open(references)
        }
        .onChange(of: browser.resultsQuery) { selection = [] }
    }

    @ViewBuilder
    private func menu(for references: Set<PullRequestReference>) -> some View {
        if !references.isEmpty {
            Button(references.count == 1 ? "Open" : "Open \(references.count) Pull Requests") { open(references) }
            if references.count == 1, let reference = references.first {
                Link("Open on GitHub", destination: reference.webURL)
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(reference.webURL.absoluteString, forType: .string)
                }
                if let author = model.browser.listings.first(where: { $0.reference == reference })?.author {
                    Divider()
                    Button("Show Only \(author)'s") {
                        _ = model.browser.addPerson(.author, login: author)
                    }
                    Button("Hide \(author)'s") {
                        _ = model.browser.addPerson(.author, isExcluded: true, login: author)
                    }
                }
            }
        }
    }

    /// In the table's order, the first ending up selected and on top.
    private func open(_ references: Set<PullRequestReference>) {
        let ordered = model.browser.listings.map(\.reference).filter(references.contains)
        for reference in ordered.reversed() { model.open(reference) }
    }
}
