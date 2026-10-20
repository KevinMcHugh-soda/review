import ReviewCore
import SwiftUI

/// The app shell: opened pull requests, the selected one's changed files, and
/// the code.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(model.pullRequests, id: \.self, selection: $model.selection) { reference in
                PullRequestRow(reference: reference, session: model.session(for: reference))
                    .contextMenu {
                        Link("Open on GitHub", destination: reference.webURL)
                        Divider()
                        Button("Close") { model.close(reference) }
                    }
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
        } content: {
            if let session = model.selectedSession {
                FilesColumn(session: session)
                    .navigationSplitViewColumnWidth(
                        min: Theme.filesMinWidth,
                        ideal: Theme.filesIdealWidth,
                        max: Theme.filesMaxWidth
                    )
                    .task(id: session.reference) {
                        if !session.hasStarted { await model.load(session) }
                    }
            } else {
                ContentUnavailableView(
                    "No Pull Request Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Open a pull request to start reviewing.")
                )
            }
        } detail: {
            if let session = model.selectedSession {
                CodeDetail(session: session)
            } else {
                Color.clear
            }
        }
        // On the split view, not a column: a title set inside the detail
        // column never reached the window's title bar.
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .focusedSceneValue(\.reviewSession, model.selectedSession)
    }

    private var title: String {
        guard let session = model.selectedSession else { return "Review" }
        return session.review?.pullRequest.title ?? session.reference.description
    }

    private var subtitle: String {
        guard let session = model.selectedSession, let pullRequest = session.review?.pullRequest else { return "" }
        return "\(session.reference) · \(pullRequest.author) · \(pullRequest.head.name) → \(pullRequest.base.name)"
    }
}
