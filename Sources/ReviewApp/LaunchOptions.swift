import AppKit
import Foundation
import ReviewKit

/// Launch-time options, for development and for scripting the app.
///
/// - `--open <pr>` opens a pull request at launch.
/// - `--file <path>` selects a changed file in it.
/// - `--mode diff|split|file` picks the view.
/// - `--expand <gap>` expands a gap between hunks (repeatable).
/// - `--navigate <action> --line <n> --column <c>` runs a navigation action
///   (`definition`, `references`, `callers`, …) at a head-side line and
///   UTF-16 column once the servers are ready.
/// - `--comment <start>[-<end>] --note <text> [--ask]` adds a draft on those
///   head-side lines, and with `--ask` asks Claude and waits for the answer.
/// - `--inspector on` shows the drafts inspector: the description and threads.
/// - `--post-sheet` opens the Post Review sheet (it only plans; nothing is
///   sent without pressing Post).
/// - `--hover <line>:<column>` shows the hover for the symbol at a head-side
///   line and UTF-16 column, once the servers are ready.
///
/// Every option is a `--flag value` pair, or a flag alone at the end. AppKit
/// reads `-key value` pairs from the command line as defaults and treats a
/// value with no flag before it as a file to open — and a launch that opens a
/// file creates no window. `--hover 73 62` did exactly that.
/// - `REVIEW_SNAPSHOT=<png>` renders the key window to that file once loading
///   settles, then quits. The agent's terminal has no Screen Recording
///   permission, so `screencapture` sees only the desktop; drawing our own
///   window needs no permission at all. SWIFTUI-RULES §9.3: visual gates beat
///   unit tests for layout.
struct LaunchOptions {
    let pullRequest: String?
    let filePath: String?
    let mode: CodeDocument.Mode?
    let expandedGaps: [Int]
    /// `--continuous on|off`: every file in one scroll, or one at a time.
    let continuous: Bool?
    let navigation: (action: NavigationAction, line: Int, column: Int)?
    let comment: (lines: ClosedRange<Int>, note: String, ask: Bool)?
    let opensPostSheet: Bool
    let showsInspector: Bool
    let hover: (line: Int, column: Int)?
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
        mode = value(after: "--mode").flatMap(CodeDocument.Mode.init(rawValue:))
        continuous = value(after: "--continuous").map { $0 == "on" }
        expandedGaps = arguments.indices.filter { arguments[$0] == "--expand" && arguments.indices.contains($0 + 1) }
            .compactMap { Int(arguments[$0 + 1]) }
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
        showsInspector = value(after: "--inspector") == "on"
        let hoverParts = value(after: "--hover")?.split(separator: ":").compactMap { Int($0) } ?? []
        hover = hoverParts.count == 2 ? (hoverParts[0], hoverParts[1]) : nil
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
        // Popovers are windows of their own as well.
        for popover in NSApp.windows where popover.isVisible && String(describing: type(of: popover)).contains("Popover") {
            write(popover, to: (path as NSString).deletingPathExtension + "-popover.png")
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
