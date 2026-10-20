import AppKit
import Foundation

/// Launch-time options, for development and for scripting the app.
///
/// - `--open <pr>` opens a pull request at launch.
/// - `--file <path>` selects a changed file in it.
/// - `--mode file` starts in whole-file mode.
/// - `REVIEW_SNAPSHOT=<png>` renders the key window to that file once loading
///   settles, then quits. The agent's terminal has no Screen Recording
///   permission, so `screencapture` sees only the desktop; drawing our own
///   window needs no permission at all. SWIFTUI-RULES §9.3: visual gates beat
///   unit tests for layout.
struct LaunchOptions {
    let pullRequest: String?
    let filePath: String?
    let wholeFile: Bool
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
        snapshotPath = environment["REVIEW_SNAPSHOT"]
    }

    /// Writes the key window's contents to `snapshotPath` as a PNG.
    @MainActor
    static func writeSnapshot(to path: String) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible),
              let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
