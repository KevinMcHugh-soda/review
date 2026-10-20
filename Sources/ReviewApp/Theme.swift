import SwiftUI

/// Centralized layout metrics + type system (SWIFTUI-RULES §2.4, §5.1).
///
/// Two rules keep this honest:
/// - **Scale** comes from semantic SwiftUI text styles only (`.caption` →
///   `.body` → `.title2` → `.largeTitle`), never hardcoded point sizes, so
///   Dynamic Type and OS metric updates keep working.
/// - **Emphasis is weight; de-emphasis is color** (`.secondary` /
///   `.tertiary`), never a lighter font weight.
///
/// When you find yourself typing the same number a third time, it belongs
/// here as a named metric.
enum Theme {
    // MARK: Window
    static let windowMinWidth: CGFloat = 900
    static let windowMinHeight: CGFloat = 560
    /// Code review wants width: a file tree, code, and a comment column.
    static let windowDefaultWidth: CGFloat = 1400
    static let windowDefaultHeight: CGFloat = 860

    // MARK: Sidebar
    static let sidebarMinWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 260
    static let sidebarMaxWidth: CGFloat = 360
    /// Wide enough for an install command to sit on one line.
    static let toolPopoverWidth: CGFloat = 380

    // MARK: Panes
    /// Standard horizontal inset for pane content.
    static let gutter: CGFloat = 12
    static let spacing: CGFloat = 10
    static let tightSpacing: CGFloat = 5

    // MARK: Type scale
    //
    // The whole app's typography lives here so hierarchy stays consistent and
    // a future restyle lands in one place.
    enum Fonts {
        /// A pull request's title in the detail column.
        static let pageTitle = Font.title2.weight(.semibold)
        /// A sidebar row's primary line.
        static let rowTitle = Font.body.weight(.medium)
        /// Metadata: repository names, counts, the footer line.
        static let meta = Font.caption
        /// Source code. Monospaced because alignment and exact characters
        /// matter; the code viewer (M2) will take its size from here.
        static let code = Font.system(.body, design: .monospaced)
    }
}
