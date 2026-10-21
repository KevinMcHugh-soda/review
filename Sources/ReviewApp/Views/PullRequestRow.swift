import ReviewCore
import SwiftUI

/// One opened pull request in the sidebar: its title and author once known,
/// the number and repository until then.
struct PullRequestRow: View {
    let reference: PullRequestReference
    let session: ReviewSession?
    let summary: PullRequestSummary?

    private var title: String? { session?.review?.pullRequest.title ?? summary?.title }
    private var author: String? { session?.review?.pullRequest.author ?? summary?.author }

    private var byline: String {
        guard let author else { return reference.description }
        return "\(author) · \(reference.repository)#\(reference.number)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title ?? "#\(reference.number)")
                .font(Theme.Fonts.rowTitle)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(byline)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(title ?? reference.description)
    }
}
