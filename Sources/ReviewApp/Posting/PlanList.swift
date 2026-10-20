import ReviewCore
import ReviewKit
import SwiftUI

/// One row per draft: where it is, where it will go, and why.
struct PlanList: View {
    let plan: ReviewPlan
    let session: ReviewSession

    var body: some View {
        List(plan.items) { item in
            if let draft = session.draft(item.draftID) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
                    Image(systemName: symbol(item.destination))
                        .foregroundStyle(tint(item.destination))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.anchor.description)
                            .font(Theme.Fonts.rowTitle)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Text(describe(item.destination))
                            .font(Theme.Fonts.meta)
                            .foregroundStyle(.secondary)
                        if !draft.body.isEmpty {
                            Text(draft.body)
                                .font(Theme.Fonts.meta)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .opacity(isSkipped(item.destination) ? 0.6 : 1)
            }
        }
        .listStyle(.inset)
    }

    private func isSkipped(_ destination: ReviewPlan.Destination) -> Bool {
        if case .skipped = destination { true } else { false }
    }

    private func symbol(_ destination: ReviewPlan.Destination) -> String {
        switch destination {
        case .line: "text.bubble"
        case .summary: "text.quote"
        case .skipped: "minus.circle"
        }
    }

    private func tint(_ destination: ReviewPlan.Destination) -> Color {
        switch destination {
        case .line: .accentColor
        case .summary: .orange
        case .skipped: .secondary
        }
    }

    private func describe(_ destination: ReviewPlan.Destination) -> String {
        switch destination {
        case let .line(_, side, startLine, line, note):
            let lines = startLine.map { "lines \($0)–\(line)" } ?? "line \(line)"
            let base = "Line comment on \(lines)\(side == .base ? " of the base" : "")"
            return switch note {
            case .reanchored(let from): "\(base) — moved from line \(from) since the PR changed"
            case .narrowedToLastLine: "\(base) — the range crosses two hunks, which GitHub refuses"
            case nil: base
            }
        case .summary(let reason):
            return switch reason {
            case .outsideDiff: "In the summary, quoted — GitHub only takes line comments on lines in the diff"
            case .notInPullRequest: "In the summary, quoted — this file is not part of the PR"
            case .couldNotReanchor: "In the summary, quoted — written on an earlier commit and those lines are gone"
            }
        case .skipped(let reason):
            return switch reason {
            case .empty: "Not posted — the draft is empty"
            case .excluded: "Not posted — kept private"
            case .alreadyPosted: "Already posted"
            }
        }
    }
}
