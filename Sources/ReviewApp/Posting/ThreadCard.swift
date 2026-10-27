import ReviewCore
import ReviewKit
import SwiftUI

/// A thread already on GitHub: where, its state, and what was said.
struct ThreadCard: View {
    let thread: ReviewThread
    @Bindable var session: ReviewSession

    private var isSelected: Bool { session.selectedThreadID == thread.id }

    var body: some View {
        let isCollapsed = session.isCollapsed(thread)
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack(spacing: Theme.tightSpacing) {
                Button(isCollapsed ? "Expand" : "Collapse", systemImage: isCollapsed ? "chevron.right" : "chevron.down") {
                    session.toggleCollapsed(thread)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(width: Theme.chevronWidth)
                .help(isCollapsed ? "Show this thread" : "Hide this thread")
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
            if isCollapsed {
                Text(MarkdownText.inline(preview))
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                ForEach(thread.comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.author)
                            .font(Theme.Fonts.meta.weight(.semibold))
                            .foregroundStyle(.secondary)
                        MarkdownText(markdown: comment.body)
                    }
                }
                replyArea
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

    /// "cursor: This jsonb_agg and GROUP BY run over… · 3 comments".
    private var preview: String {
        guard let first = thread.comments.first else { return "No comments" }
        let text = GitHubMarkdown.removingHiddenComments(first.body)
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let more = thread.comments.count > 1 ? " · \(thread.comments.count) comments" : ""
        return "\(first.author): \(text)\(more)"
    }

    /// A reply field, and Resolve beside it. Both act on GitHub at once, as
    /// its own buttons do.
    private var replyArea: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            HStack(alignment: .bottom, spacing: Theme.tightSpacing) {
                TextField("Reply on GitHub", text: Binding(
                    get: { session.threadReplies[thread.id] ?? "" },
                    set: { session.threadReplies[thread.id] = $0 }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                Button("Reply") { Task { await session.reply(to: thread) } }
                    .disabled((session.threadReplies[thread.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || session.threadActions[thread.id] != nil)
                    .help("Posts to GitHub now")
            }
            HStack(spacing: Theme.spacing) {
                Button(thread.isResolved ? "Unresolve" : "Resolve") { Task { await session.toggleResolved(thread) } }
                    .buttonStyle(.link)
                    .disabled(session.threadActions[thread.id] != nil)
                if session.threadActions[thread.id] != nil {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(Theme.Fonts.meta)
            if let error = session.threadErrors[thread.id] {
                Text(error)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
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
