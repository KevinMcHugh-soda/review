import ReviewCore
import SwiftUI

/// Settings › Repositories: the repositories whose pull requests the inbox
/// searches. Add with `owner/repo` or a URL; remove with − or Delete.
struct RepositoriesSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<RepositoryName> = []
    @State private var text = ""
    @State private var isInvalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text("Pull requests you're asked to review, assigned, or wrote, in these repositories, fill the sidebar. With none, every repository is searched.")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selection) {
                ForEach(model.trackedRepositories, id: \.self) { repository in
                    Text(repository.description)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .tag(repository)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .onDeleteCommand { removeSelected() }
            .overlay {
                Text("All repositories")
                    .foregroundStyle(.tertiary)
                    .opacity(model.trackedRepositories.isEmpty ? 1 : 0)
                    .accessibilityHidden(!model.trackedRepositories.isEmpty)
            }

            HStack(spacing: Theme.tightSpacing) {
                Button("Remove", systemImage: "minus", action: removeSelected)
                    .labelStyle(.iconOnly)
                    .disabled(selection.isEmpty)
                TextField("owner/repo", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .onChange(of: text) { isInvalid = false }
                Button("Add", action: add)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Not a repository — use owner/repo or its GitHub URL.")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.red)
                .opacity(isInvalid ? 1 : 0)
                .accessibilityHidden(!isInvalid)
        }
        .padding(Theme.sheetPadding)
        .frame(width: Theme.settingsWidth, height: Theme.settingsHeight)
    }

    private func add() {
        do {
            try model.track(text)
            text = ""
        } catch {
            isInvalid = true
        }
    }

    private func removeSelected() {
        model.untrack(selection)
        selection = []
    }
}
