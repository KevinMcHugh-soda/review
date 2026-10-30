import ReviewCore
import SwiftUI

/// A pull request's title, tagged when it is a draft, merged or closed, and
/// when it is already open in the sidebar.
struct BrowseTitleCell: View {
    let listing: PullRequestListing
    let isInSidebar: Bool

    var body: some View {
        HStack(spacing: Theme.tightSpacing) {
            Text(listing.title)
                .lineLimit(1)
                .truncationMode(.tail)
            if listing.status != .open {
                StateTag(text: listing.status.title.lowercased())
            }
            if isInSidebar {
                StateTag(text: "in sidebar")
            }
        }
        .help(listing.title)
    }
}
