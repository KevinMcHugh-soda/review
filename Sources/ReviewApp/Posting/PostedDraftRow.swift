import ReviewCore
import SwiftUI

/// A draft that has gone to GitHub: kept for reference, out of the way.
struct PostedDraftRow: View {
    let draft: DraftComment
    let session: ReviewSession

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Button(draft.anchor.description) { session.reveal(draft) }
                    .buttonStyle(.link)
                    .lineLimit(1)
                Text(draft.body)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let url = draft.posted?.reviewURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.forward.square")
                }
                .help("Open the review on GitHub")
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) { session.deleteDraft(draft.id) }
        }
    }
}
