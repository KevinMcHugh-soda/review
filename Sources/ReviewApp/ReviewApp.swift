import SwiftUI

// Not `main.swift` — see the note in Sources/ReviewCLI/Main.swift.
@main
struct ReviewApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: Theme.windowMinWidth, minHeight: Theme.windowMinHeight)
                .task { await model.start(applying: .current) }
        }
        .defaultSize(width: Theme.windowDefaultWidth, height: Theme.windowDefaultHeight)
        .commands {
            ReviewCommands()
            CommandGroup(after: .sidebar) {
                Button("Refresh Review Requests") { Task { await model.refreshInbox() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        // One window: `review://` links open in it, not in a new one.
        .handlesExternalEvents(matching: ["review"])
    }
}
