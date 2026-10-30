import ReviewKit
import SwiftUI

/// Settings › File Order: per repository, the directories whose changes to
/// read first. Drag to reorder; files under none of them go where
/// Everything Else is.
struct FileOrderSettings: View {
    @Environment(AppModel.self) private var model
    @State private var repository: String?
    @State private var selection: Set<String> = []
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text("Changed files in these directories come first, in this order — the most specific match wins. Drag to reorder. Use * within a name and ** across directories: internal/*/*.yaml.")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Repository", selection: $repository) {
                ForEach(model.orderableRepositories, id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
            }
            .disabled(model.orderableRepositories.isEmpty)

            List(selection: $selection) {
                ForEach(rules, id: \.self) { rule in
                    row(for: rule)
                        .tag(rule)
                        .selectionDisabled(rule == FileOrder.everythingElse)
                }
                .onMove { offsets, destination in
                    save(ListReordering.moving(rules, fromOffsets: offsets, toOffset: destination))
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .onDeleteCommand(perform: removeSelected)
            .disabled(repository == nil)

            HStack(spacing: Theme.tightSpacing) {
                Button("Remove", systemImage: "minus", action: removeSelected)
                    .labelStyle(.iconOnly)
                    .disabled(selection.isEmpty)
                TextField("db, pkg/sponsor or internal/*/*.yaml", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(repository == nil || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.sheetPadding)
        .frame(width: Theme.settingsWidth, height: Theme.settingsHeight)
        .onAppear(perform: chooseRepository)
        .onChange(of: model.orderableRepositories) { chooseRepository() }
        .onChange(of: repository) { selection = [] }
    }

    /// The rules as edited: Everything Else always shown, so a directory can
    /// be dragged below it.
    private var rules: [String] {
        guard let repository else { return [] }
        return model.fileOrder(for: repository).withEverythingElse
    }

    @ViewBuilder
    private func row(for rule: String) -> some View {
        if rule == FileOrder.everythingElse {
            Text("Everything else")
                .italic()
                .foregroundStyle(.secondary)
        } else {
            Text(FileOrder.isPattern(rule) ? rule : rule + "/")
                .font(Theme.Fonts.codeSmall)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The open pull request's repository, else the first there is.
    private func chooseRepository() {
        let names = model.orderableRepositories
        if let repository, names.contains(repository) { return }
        let open = model.selection.map { FileOrderStore.key($0.repositorySlug) }
        repository = open.flatMap { names.contains($0) ? $0 : nil } ?? names.first
    }

    /// A new directory goes just above Everything Else.
    private func add() {
        guard repository != nil else { return }
        let directory = text.trimmingCharacters(in: .whitespaces)
        guard !directory.isEmpty else { return }
        var rules = rules.filter { $0 != directory }
        rules.insert(directory, at: rules.firstIndex(of: FileOrder.everythingElse) ?? rules.endIndex)
        save(rules)
        text = ""
    }

    private func removeSelected() {
        save(rules.filter { !selection.contains($0) || $0 == FileOrder.everythingElse })
        selection = []
    }

    private func save(_ rules: [String]) {
        guard let repository else { return }
        model.setFileOrder(FileOrder(rules: rules), for: repository)
    }
}
