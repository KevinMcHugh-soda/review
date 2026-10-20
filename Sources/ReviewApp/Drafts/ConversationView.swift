import ReviewCore
import SwiftUI

/// A conversation with Claude: the turns so far, the one being written, and a
/// field for the next question.
struct ConversationView: View {
    let turns: [ConversationTurn]
    let progress: AskProgress?
    @Binding var followUp: String
    let canFollowUp: Bool
    let isSelected: Bool
    let ask: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ForEach(turns) { turn in
                TurnView(turn: turn)
            }
            if let progress {
                VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                    if progress.text.isEmpty {
                        Label(progress.activity ?? "Thinking…", systemImage: "sparkle")
                            .font(Theme.Fonts.meta)
                            .foregroundStyle(.secondary)
                    } else {
                        MarkdownText(markdown: progress.text)
                        if let activity = progress.activity {
                            Text(activity).font(Theme.Fonts.meta).foregroundStyle(.secondary)
                        }
                    }
                    Button("Stop", systemImage: "stop.circle", action: stop)
                        .buttonStyle(.borderless)
                        .font(Theme.Fonts.meta)
                }
            } else if canFollowUp {
                HStack(alignment: .bottom, spacing: Theme.tightSpacing) {
                    TextField("Ask a follow-up", text: $followUp, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...6)
                        .onSubmit(ask)
                    Button("Ask", systemImage: "arrow.up.circle.fill", action: ask)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help(isSelected ? "Ask (⌘↩)" : "Ask")
                }
            }
        }
    }
}

private struct TurnView: View {
    let turn: ConversationTurn

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            HStack(spacing: Theme.tightSpacing) {
                Text(turn.author == .claude ? "Claude" : "You")
                    .font(Theme.Fonts.meta.weight(.semibold))
                if let cost = turn.costUSD {
                    Text(cost, format: .currency(code: "USD").precision(.fractionLength(2)))
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(.tertiary)
                        .help("What this answer cost")
                }
            }
            .foregroundStyle(.secondary)
            if turn.isError {
                Label(turn.text, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else if turn.author == .claude {
                MarkdownText(markdown: turn.text)
            } else {
                Text(turn.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
