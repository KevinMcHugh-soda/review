import ReviewCore
import SwiftUI

/// One opened pull request in the sidebar. Title and author arrive in M2,
/// once the PR is fetched; until then the number and repository stand in.
struct PullRequestRow: View {
    let reference: PullRequestReference

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("#\(reference.number)")
                .font(Theme.Fonts.rowTitle)
                .lineLimit(1)
            Text(reference.repositorySlug)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contextMenu {
            Link("Open on GitHub", destination: reference.webURL)
        }
    }
}
