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
                .task { await model.start() }
        }
        .defaultSize(width: Theme.windowDefaultWidth, height: Theme.windowDefaultHeight)
    }
}
