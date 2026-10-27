import SwiftUI

/// The toolbar's one Refresh: everything waiting on you, your own pull
/// requests, and the status of every open one. A spinner while it runs.
struct RefreshButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Refresh", systemImage: "arrow.clockwise") {
            Task { await model.refresh() }
        }
        .disabled(model.isLoadingInbox)
        .opacity(model.isLoadingInbox ? 0 : 1)
        .overlay {
            ProgressView()
                .controlSize(.small)
                .opacity(model.isLoadingInbox ? 1 : 0)
                .accessibilityHidden(!model.isLoadingInbox)
        }
        .help(help)
    }

    private var help: String {
        guard let lastRefreshed = model.lastRefreshed else { return "Refresh pull requests (⌘R)" }
        return "Refresh pull requests (⌘R) — last refreshed \(lastRefreshed.formatted(date: .omitted, time: .shortened))"
    }
}
