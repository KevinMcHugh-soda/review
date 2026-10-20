import ReviewCore
import SwiftUI

/// A thread already on GitHub: where, its state, and what was said.
struct ThreadCard: View {
    let thread: ReviewThread
    let session: ReviewSession

    private var isSelected: Bool { session.selectedThreadID == thread.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack(spacing: Theme.tightSpacing) {
                Button {
                    session.reveal(thread)
                } label: {
                    Text(location)
                        .font(Theme.Fonts.panelTitle)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .buttonStyle(.link)
                if thread.isResolved { StateTag(text: "resolved") }
                if thread.isOutdated { StateTag(text: "outdated") }
                Spacer(minLength: 0)
                if let url = thread.comments.first?.url {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .help("Open on GitHub")
                }
            }
            ForEach(thread.comments) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.author)
                        .font(Theme.Fonts.meta.weight(.semibold))
                        .foregroundStyle(.secondary)
                    MarkdownText(markdown: comment.body)
                }
            }
        }
        .padding(Theme.gutter)
        .background(.background.secondary, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .opacity(thread.isResolved ? 0.7 : 1)
    }

    private var location: String {
        if let lines = thread.lines {
            lines.count == 1 ? "\(thread.path):\(lines.lowerBound)" : "\(thread.path):\(lines.lowerBound)–\(lines.upperBound)"
        } else {
            "\(thread.path):\(thread.originalLine ?? 0)"
        }
    }
}

/// "resolved", "outdated".
struct StateTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Fonts.badge)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.badgePaddingHorizontal)
            .padding(.vertical, Theme.badgePaddingVertical)
            .background(.quaternary, in: .capsule)
    }
}
