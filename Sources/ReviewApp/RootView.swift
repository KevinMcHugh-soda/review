import ReviewCore
import SwiftUI

/// The app shell: opened pull requests in the sidebar, the selected one in
/// the detail column. The detail becomes file list + code viewer in M2.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(model.pullRequests, id: \.self, selection: $model.selection) { reference in
                PullRequestRow(reference: reference)
            }
            .navigationSplitViewColumnWidth(
                min: Theme.sidebarMinWidth,
                ideal: Theme.sidebarIdealWidth,
                max: Theme.sidebarMaxWidth
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                OpenPullRequestField()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ToolStatusFooter()
            }
            .overlay {
                if model.pullRequests.isEmpty {
                    ContentUnavailableView(
                        "No Pull Requests",
                        systemImage: "arrow.triangle.pull",
                        description: Text("Paste a pull request URL above.")
                    )
                }
            }
        } detail: {
            if let selection = model.selection {
                PullRequestPlaceholder(reference: selection)
            } else {
                ContentUnavailableView(
                    "No Pull Request Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Open a pull request to start reviewing.")
                )
            }
        }
        .navigationTitle("Review")
    }
}
