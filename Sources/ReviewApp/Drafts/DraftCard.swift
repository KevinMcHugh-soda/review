import ReviewCore
import SwiftUI

/// One draft: where it is, the code it is about, the note, and its
/// conversation with Claude.
struct DraftCard: View {
    let draft: DraftComment
    @Bindable var session: ReviewSession
    @FocusState.Binding var focusedDraft: UUID?

    private var isSelected: Bool { session.selectedDraftID == draft.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            header
            // Unwrapped, scrolling sideways: wrapped code in a narrow column
            // stops looking like code.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(draft.anchor.quotedLines.prefix(Theme.maxQuotedLines).joined(separator: "\n"))
                    .font(Theme.Fonts.codeSmall)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .padding(Theme.tightSpacing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Theme.codeBlockCornerRadius))

            TextEditor(text: Binding(
                get: { draft.body },
                set: { session.setBody($0, of: draft.id) }
            ))
            .font(Theme.Fonts.note)
            .scrollContentBackground(.hidden)
            .frame(minHeight: Theme.noteMinHeight, maxHeight: Theme.noteMaxHeight)
            .padding(Theme.tightSpacing)
            .background(.background, in: .rect(cornerRadius: Theme.codeBlockCornerRadius))
            .overlay(alignment: .topLeading) {
                Text("What do you think?")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Theme.spacing)
                    .padding(.vertical, Theme.tightSpacing + 1)
                    .opacity(draft.body.isEmpty ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .focused($focusedDraft, equals: draft.id)

            Toggle("Keep private", isOn: Binding(
                get: { draft.isExcludedFromReview },
                set: { session.setExcluded($0, draft.id) }
            ))
            .toggleStyle(.checkbox)
            .font(Theme.Fonts.meta)
            .help("Leave this out when the review is posted")

            if draft.conversation.isEmpty, session.asks[draft.id] == nil {
                Button("Ask Claude", systemImage: "sparkle") { session.ask(about: draft.id) }
                    .help(isSelected ? "Ask Claude about this (⌘↩)" : "Ask Claude about this")
                    .disabled(!session.canAsk)
            } else {
                ConversationView(
                    turns: visibleTurns,
                    progress: session.asks[draft.id],
                    followUp: Binding(
                        get: { session.followUps[draft.id] ?? "" },
                        set: { session.followUps[draft.id] = $0 }
                    ),
                    canFollowUp: session.canAsk && draft.claudeSessionID != nil,
                    isSelected: isSelected,
                    ask: { session.ask(about: draft.id) },
                    stop: { session.cancelAsk(draft.id) }
                )
            }
        }
        .padding(Theme.gutter)
        .background(.background.secondary, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .contentShape(.rect)
        .onTapGesture { session.selectedDraftID = draft.id }
        .contextMenu {
            Button("Show in Code") { session.reveal(draft) }
            Divider()
            Button("Delete Draft", role: .destructive) { session.deleteDraft(draft.id) }
        }
    }

    /// The conversation without its opening question when that is just the
    /// note, which the card already shows above.
    private var visibleTurns: [ConversationTurn] {
        guard let first = draft.conversation.first, first.author == .reviewer,
              first.text == draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return draft.conversation }
        return Array(draft.conversation.dropFirst())
    }

    private var header: some View {
        HStack(spacing: Theme.tightSpacing) {
            Button {
                session.reveal(draft)
            } label: {
                Text(draft.anchor.description)
                    .font(Theme.Fonts.panelTitle)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .buttonStyle(.link)
            .help("Show in code")
            if draft.anchor.side == .base {
                Tag(text: "base")
            }
            if !draft.anchor.isInPullRequest {
                Tag(text: "not in PR")
            }
            if session.isStale(draft) {
                Tag(text: "older commit")
                    .help("Written before the PR's latest push; the lines may have moved.")
            }
            Spacer(minLength: 0)
            Button("Delete Draft", systemImage: "trash") { session.deleteDraft(draft.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}

/// A small capsule label: "base", "not in PR".
private struct Tag: View {
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
