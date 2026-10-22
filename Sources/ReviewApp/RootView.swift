import ReviewCore
import SwiftUI

/// The app shell: opened pull requests, the selected one's changed files, and
/// the code.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        @Bindable var model = model

        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $model.selection) {
                ForEach(shownStatuses, id: \.self) { status in
                    let group = model.pullRequests(with: status)
                    Section {
                        ForEach(group, id: \.self) { reference in
                            PullRequestRow(
                                reference: reference,
                                session: model.session(for: reference),
                                summary: model.summaries[reference]
                            )
                            .tag(reference)
                            .contextMenu { rowMenu(reference, in: group) }
                        }
                        // Drag to reorder within the group; the order is
                        // saved and survives a relaunch.
                        .onMove { model.moveOpenPullRequests(in: status, fromOffsets: $0, toOffset: $1) }
                    } header: {
                        GroupHeader(status: status, count: group.count)
                    }
                }
                InboxSection(title: "Waiting on You", items: model.waitingInbox) {
                    if let error = model.inboxError {
                        Text(error).lineLimit(3)
                    } else if model.trackedRepositories.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nothing waiting on you in any repository.")
                            SettingsLink { Text("Choose Repositories…") }
                                .buttonStyle(.link)
                        }
                    } else {
                        Text("Nothing waiting on you in ^[\(model.trackedRepositories.count) repository](inflect: true).")
                    }
                }
                InboxSection(title: "Your Pull Requests", items: model.authoredInbox) {
                    if model.inboxError == nil {
                        Text("No open pull requests of yours.")
                    }
                }
            }
            // A group appearing or emptying makes a new list. Inserting or
            // removing a collapsible section in place leaves AppKit's outline
            // view holding the freed section, and its next tracking-area pass
            // crashes (EXC_BAD_ACCESS in -[NSOutlineView rowForItem:]).
            .id(shownStatuses)
            .toolbar {
                ToolbarItem {
                    RefreshButton()
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
        .task {
            let options = LaunchOptions.current
            if options.showsSidebar { columnVisibility = .all }
            if options.opensSettings { openSettings() }
        }

    }

    @ViewBuilder
    private func rowMenu(_ reference: PullRequestReference, in group: [PullRequestReference]) -> some View {
        Link("Open on GitHub", destination: reference.webURL)
        Divider()
        // The keyboard and menu way to do what a drag does.
        Button("Move to Top") { model.moveOpenPullRequestToTop(reference) }
            .disabled(group.first == reference)
        Button("Move Up") { model.moveOpenPullRequest(reference, by: -1) }
            .disabled(group.first == reference)
        Button("Move Down") { model.moveOpenPullRequest(reference, by: 1) }
            .disabled(group.last == reference)
        Divider()
        Button("Close") { model.close(reference) }
    }

    /// The status groups with a PR in them; empty ones are not shown.
    private var shownStatuses: [PullRequestStatus] {
        PullRequestStatus.allCases.filter { !model.pullRequests(with: $0).isEmpty }
    }

    private var title: String {
        guard let session = model.selectedSession else { return "Review" }
        return session.review?.pullRequest.title ?? session.reference.description
    }

    private var subtitle: String {
        guard let session = model.selectedSession, let pullRequest = session.review?.pullRequest else { return "" }
        return "\(pullRequest.status.title) · \(session.reference) · \(pullRequest.author) · \(pullRequest.head.name) → \(pullRequest.base.name)"
    }
}
