import ReviewCore
import SwiftUI

/// A pull request from the inbox: title, author, repository, and how long
/// since anything happened. The author is left out of the reviewer's own.
struct InboxRow: View {
    let item: InboxItem

    private var byline: String {
        let number = "\(item.reference.repository)#\(item.reference.number)"
        return item.isAuthored ? number : "\(item.author) · \(number)"
    }

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
                if !item.isAuthored, item.reasons.contains(.assigned) {
                    StateTag(text: "assigned")
                }
            }
            HStack(spacing: Theme.tightSpacing) {
                Text(byline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(item.updatedAt, format: .relative(presentation: .named))
                    .lineLimit(1)
            }
            .font(Theme.Fonts.meta)
            .foregroundStyle(.secondary)
        }
        .help("\(item.title)\n\(item.reference) by \(item.author)")
    }
}
