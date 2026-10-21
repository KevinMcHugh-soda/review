import SwiftUI

/// Beside a pull request's title in the sidebar when some reviewer approves it.
struct ApprovedMark: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(Theme.Fonts.meta)
            .foregroundStyle(.green)
            .accessibilityLabel("Approved")
            .help("Approved")
    }
}
