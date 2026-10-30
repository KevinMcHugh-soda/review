import ReviewCore
import SwiftUI

/// The browser's middle column: where to search. Everything involving the
/// reviewer, the tracked repositories together, then each repository —
/// tracked ones first, then every other the reviewer can see.
struct BrowseScopesColumn: View {
    @Environment(AppModel.self) private var model
    @State private var filterText = ""

    var body: some View {
        @Bindable var browser = model.browser

        List(selection: $browser.scope) {
            Section {
                Label(BrowseScope.involvingMe.title, systemImage: "person.crop.circle")
                    .tag(BrowseScope.involvingMe)
                    .help("Pull requests you wrote, were asked to review, were assigned, commented on or were mentioned in")
                if !model.trackedRepositories.isEmpty {
                    Label(BrowseScope.tracked.title, systemImage: "star")
                        .tag(BrowseScope.tracked)
                        .help(model.trackedRepositories.map(\.description).joined(separator: "\n"))
                }
            }
            if !shownTracked.isEmpty {
                Section("Tracked") {
                    ForEach(shownTracked, id: \.self) { repository in
                        BrowseRepositoryRow(repository: repository, isTracked: true)
                    }
                }
            }
            Section("Repositories") {
                ForEach(shownOthers, id: \.self) { repository in
                    BrowseRepositoryRow(repository: repository, isTracked: false)
                }
                if shownOthers.isEmpty {
                    Group {
                        if let error = browser.repositoriesError {
                            Text(error).lineLimit(3)
                        } else if browser.isLoadingRepositories {
                            Text("Loading repositories…")
                        } else if !filterText.isEmpty {
                            Text("No repositories match.")
                        }
                    }
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TextField("Filter repositories", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, Theme.spacing)
        }
        .task { await browser.loadRepositories() }
    }

    private func matches(_ repository: RepositoryName) -> Bool {
        let filter = filterText.trimmingCharacters(in: .whitespaces)
        return filter.isEmpty || repository.description.localizedCaseInsensitiveContains(filter)
    }

    private var shownTracked: [RepositoryName] {
        model.trackedRepositories.filter(matches)
    }

    /// Most recently pushed first, as GitHub returns them.
    private var shownOthers: [RepositoryName] {
        let tracked = Set(model.trackedRepositories)
        return model.browser.repositories.filter { !tracked.contains($0) && matches($0) }
    }
}
