import SwiftUI

/// Above the file list once the PR has moved on since the reviewer last
/// viewed it: All Changes, or only what changed since — GitHub's "changes
/// since last view".
struct ChangesSinceViewedBar: View {
    @Bindable var session: ReviewSession
    let changes: ReviewSession.ChangesSinceViewed

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Picker("Show", selection: $session.isShowingChangesSinceViewed) {
                Text("All Changes").tag(false)
                Text("Since Last View").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!session.canShowChangesSinceViewed)
            .help("Every change in the PR, or only what changed since you last viewed it (⌘5)")
            Text(note)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.spacing)
        .background(.bar)
    }

    private var note: String {
        switch changes {
        case .loading:
            "New commits since your last view. Comparing…"
        case .loaded(let review):
            if let since = review.changesSince, !since.isExact {
                "Since \(since.commit.prefix(7)). May include \(review.pullRequest.base.name)'s changes: the author brought them in with conflicts."
            } else {
                "What changed after you viewed it at \(review.changesSince?.commit.prefix(7) ?? "")."
            }
        case .unavailable(let message):
            message
        }
    }
}
