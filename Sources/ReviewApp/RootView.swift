import ReviewCore
import SwiftUI

/// The app shell: opened pull requests, the selected one's changed files, and
/// the code.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: $model.selection) {
                if !model.pullRequests.isEmpty {
                    Section("Open") {
                        ForEach(model.pullRequests, id: \.self) { reference in
                            PullRequestRow(reference: reference, session: model.session(for: reference))
                                .tag(reference)
                                .contextMenu {
                                    Link("Open on GitHub", destination: reference.webURL)
                                    Divider()
                                    Button("Close") { model.close(reference) }
                                }
                        }
                    }
                }
                Section {
                    ForEach(model.unopenedInbox) { item in
                        InboxRow(item: item)
                            .tag(item.reference)
                            .contextMenu {
                                Link("Open on GitHub", destination: item.reference.webURL)
                            }
                    }
                    if let error = model.inboxError {
                        Text(error)
                            .font(Theme.Fonts.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else if model.unopenedInbox.isEmpty, !model.isLoadingInbox {
                        Text("Nothing waiting on you.")
                            .font(Theme.Fonts.meta)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Review Requested")
                        Spacer()
                        if model.isLoadingInbox {
                            ProgressView().controlSize(.mini)
                        } else {
                            Button("Refresh", systemImage: "arrow.clockwise") {
                                Task { await model.refreshInbox() }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Refresh review requests (⌘R)")
                        }
                    }
                }
            }
            .onChange(of: model.selection) { _, reference in model.didSelect(reference) }
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
        .onOpenURL { model.handle($0) }

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
