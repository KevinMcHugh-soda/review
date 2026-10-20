import ReviewCore
import SwiftUI

/// One opened pull request in the sidebar: its title once loaded, the number
/// and repository until then.
struct PullRequestRow: View {
    let reference: PullRequestReference
    let session: ReviewSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session?.review?.pullRequest.title ?? "#\(reference.number)")
                .font(Theme.Fonts.rowTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(reference.description)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(session?.review?.pullRequest.title ?? reference.description)
    }
}
