import ReviewCore
import SwiftUI

/// Where a pull request's reviews stand, as an icon and words so it never
/// relies on colour alone. Empty when nobody has had a say.
struct ReviewStateLabel: View {
    let state: PullRequestListing.ReviewState?

    var body: some View {
        if let state {
            Label {
                Text(state.title)
                    .foregroundStyle(state == .reviewRequired ? .secondary : .primary)
            } icon: {
                Image(systemName: symbol(for: state))
                    .foregroundStyle(color(for: state))
            }
            .lineLimit(1)
        }
    }

    private func symbol(for state: PullRequestListing.ReviewState) -> String {
        switch state {
        case .approved: "checkmark.circle.fill"
        case .changesRequested: "exclamationmark.circle.fill"
        case .reviewRequired: "circle.dashed"
        }
    }

    private func color(for state: PullRequestListing.ReviewState) -> Color {
        switch state {
        case .approved: .green
        case .changesRequested: .orange
        case .reviewRequired: .secondary
        }
    }
}
