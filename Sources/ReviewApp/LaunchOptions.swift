import AppKit
import Foundation

/// Launch-time options, for development and for scripting the app.
///
/// - `--open <pr>` opens a pull request at launch.
/// - `--file <path>` selects a changed file in it.
/// - `--mode file` starts in whole-file mode.
/// - `--navigate <action> --line <n> --column <c>` runs a navigation action
///   (`definition`, `references`, `callers`, …) at a head-side line and
///   UTF-16 column once the servers are ready.
/// - `--comment <start>[-<end>] --note <text> [--ask]` adds a draft on those
///   head-side lines, and with `--ask` asks Claude and waits for the answer.
/// - `--post-sheet` opens the Post Review sheet (it only plans; nothing is
///   sent without pressing Post).
/// - `REVIEW_SNAPSHOT=<png>` renders the key window to that file once loading
///   settles, then quits. The agent's terminal has no Screen Recording
///   permission, so `screencapture` sees only the desktop; drawing our own
///   window needs no permission at all. SWIFTUI-RULES §9.3: visual gates beat
///   unit tests for layout.
struct LaunchOptions {
    let pullRequest: String?
    let filePath: String?
    let wholeFile: Bool
    let navigation: (action: NavigationAction, line: Int, column: Int)?
    let comment: (lines: ClosedRange<Int>, note: String, ask: Bool)?
    let opensPostSheet: Bool
    let snapshotPath: String?

    static let current = Self(
        arguments: ProcessInfo.processInfo.arguments,
        environment: ProcessInfo.processInfo.environment
    )

    init(arguments: [String], environment: [String: String]) {
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        pullRequest = value(after: "--open")
        filePath = value(after: "--file")
        wholeFile = value(after: "--mode") == "file"
        if let action = value(after: "--navigate").flatMap(NavigationAction.init(rawValue:)),
           let line = value(after: "--line").flatMap(Int.init)
        {
            navigation = (action, line, value(after: "--column").flatMap(Int.init) ?? 0)
        } else {
            navigation = nil
        }
        if let spec = value(after: "--comment") {
            let bounds = spec.split(separator: "-").compactMap { Int($0) }
            let lines = (bounds.first ?? 1)...(bounds.last ?? bounds.first ?? 1)
            comment = (lines, value(after: "--note") ?? "", arguments.contains("--ask"))
        } else {
            comment = nil
        }
        opensPostSheet = arguments.contains("--post-sheet")
        snapshotPath = environment["REVIEW_SNAPSHOT"]
    }

    /// Writes the main window's contents to `path` as a PNG, and an attached
    /// sheet — a separate window — beside it as `<name>-sheet.png`.
    @MainActor
    static func writeSnapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil }) else { return }
        write(window, to: path)
        if let sheet = window.attachedSheet {
            write(sheet, to: (path as NSString).deletingPathExtension + "-sheet.png")
        }
    }

    @MainActor
    private static func write(_ window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
