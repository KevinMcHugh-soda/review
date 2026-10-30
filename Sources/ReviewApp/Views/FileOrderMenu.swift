import ReviewCore
import ReviewKit
import SwiftUI

/// A changed file's context-menu items for its repository's file order:
/// show one of its directories first or last, or open the editor.
struct FileOrderMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let path: String
    let reference: PullRequestReference

    var body: some View {
        let directories = Self.directories(of: path)
        if !directories.isEmpty {
            Menu("Show First") {
                ForEach(directories, id: \.self) { directory in
                    Button(directory + "/") { update { $0.putting(first: directory) } }
                }
            }
            Menu("Show Last") {
                ForEach(directories, id: \.self) { directory in
                    Button(directory + "/") { update { $0.putting(last: directory) } }
                }
            }
        }
        Button("Edit File Order…") {
            UserDefaults.standard.set(SettingsView.Tab.fileOrder.rawValue, forKey: SettingsView.tabKey)
            openSettings()
        }
    }

    private func update(_ change: (FileOrder) -> FileOrder) {
        let repository = reference.repositorySlug
        model.setFileOrder(change(model.fileOrder(for: repository)), for: repository)
    }

    /// `pkg/sponsor/handler.go` → `pkg/sponsor`, `pkg`: nearest first.
    static func directories(of path: String) -> [String] {
        let components = path.split(separator: "/").dropLast()
        return components.indices.reversed().map { components[...$0].joined(separator: "/") }
    }
}
