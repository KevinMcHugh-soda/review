import ReviewCore
import SwiftUI

/// A pull request waiting on your review: title, repository, author, and how
/// long since anything happened.
struct InboxRow: View {
    let item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.tightSpacing) {
                Text(item.title)
                    .font(Theme.Fonts.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if item.isDraft {
                    StateTag(text: "draft")
                }
            }
            HStack(spacing: Theme.tightSpacing) {
                Text("\(item.reference.repository)#\(item.reference.number) · \(item.author)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(item.updatedAt, format: .relative(presentation: .named))
                    .lineLimit(1)
            }
            .font(Theme.Fonts.meta)
            .foregroundStyle(.secondary)
        }
        .help("\(item.title)\n\(item.reference)")
    }
}
