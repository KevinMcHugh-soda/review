import AppKit
import ReviewKit
import ReviewSyntax
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

    // MARK: Files column
    static let filesMinWidth: CGFloat = 240
    static let filesIdealWidth: CGFloat = 300
    static let filesMaxWidth: CGFloat = 480

    // MARK: Results panel
    static let resultsMinHeight: CGFloat = 120
    static let resultsIdealHeight: CGFloat = 220
    static let resultsMaxHeight: CGFloat = 600
    /// The divider's drag target, much taller than the hairline it draws.
    static let dividerHitHeight: CGFloat = 8
    /// Room for a four-digit line number in a result row.
    static let resultLineNumberWidth: CGFloat = 36

    // MARK: Drafts inspector
    static let inspectorMinWidth: CGFloat = 300
    static let inspectorIdealWidth: CGFloat = 380
    static let inspectorMaxWidth: CGFloat = 640
    static let cardCornerRadius: CGFloat = 8
    static let codeBlockCornerRadius: CGFloat = 6
    static let noteMinHeight: CGFloat = 54
    static let noteMaxHeight: CGFloat = 220
    /// Quoted code in a draft card is a reminder, not the code itself.
    static let maxQuotedLines = 6
    static let readingTopInset: CGFloat = 28
    static let badgePaddingHorizontal: CGFloat = 6
    static let badgePaddingVertical: CGFloat = 1

    // MARK: Hover
    static let hoverMaxWidth: CGFloat = 520
    static let hoverMaxHeight: CGFloat = 360

    // MARK: Post sheet
    static let postSheetWidth: CGFloat = 620
    static let postSheetHeight: CGFloat = 640
    static let summaryHeight: CGFloat = 90
    static let sheetPadding: CGFloat = 20

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
        /// A file's +/− counts: tabular figures so a column of them aligns.
        static let counts = Font.caption.monospacedDigit().weight(.medium)
        /// Source code in SwiftUI views; the code viewer itself uses
        /// `Code.font`.
        static let code = Font.system(.body, design: .monospaced)
        /// Code in result lists, a step down so a row stays one line.
        static let codeSmall = Font.system(.callout, design: .monospaced)
        /// The reviewer's own words in a draft.
        static let note = Font.body
        /// "base", "not in PR".
        static let badge = Font.caption2.weight(.medium)
        /// A panel's header: the results panel's "References · 3 results".
        static let panelTitle = Font.callout.weight(.semibold)
    }

    // MARK: Code

    /// The code viewer's palette and metrics. AppKit types, because the
    /// viewer is an NSTextView; every colour is a dynamic system colour, so
    /// light and dark both come for free.
    enum Code {
        /// Monospaced at the body text style's size, so it tracks the
        /// system's text size rather than a number picked here.
        static var font: NSFont {
            NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        }

        static var gutterFont: NSFont {
            NSFont.monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular)
        }

        /// Tabs render four columns wide — Go is tab-indented throughout.
        static let tabWidth = 4
        /// Extra leading between lines; diff bands cover it, so they stay
        /// continuous.
        static let lineSpacing: CGFloat = 2
        static let textInset = NSSize(width: 6, height: 6)
        static let gutterPadding: CGFloat = 8
        /// The leftmost gutter column, where a draft's bubble sits.
        static let draftMarkWidth: CGFloat = 16
        static let draftMark = NSColor.controlAccentColor
        static let threadMark = NSColor.secondaryLabelColor
        /// How far below the viewport's top edge the "file being read" is
        /// taken from.
        static let topRowProbe: CGFloat = 24
        /// How long the pointer rests on a symbol before its hover shows.
        static let hoverDelay = Duration.milliseconds(600)
        static let gutterColumnGap: CGFloat = 6

        static let text = NSColor.textColor
        static let background = NSColor.textBackgroundColor

        static func color(for kind: TokenKind) -> NSColor {
            switch kind {
            case .keyword: .systemPink
            case .string: .systemRed
            case .escape: .systemOrange
            case .comment: .secondaryLabelColor
            case .number, .constant: .systemPurple
            case .type: .systemTeal
            case .function: .systemBlue
            case .property: .systemIndigo
            case .parameter: .systemBrown
            case .operator: .secondaryLabelColor
            case .tag: .systemBlue
            }
        }

        /// The full-width band behind a row. Nil for plain context.
        static func band(for kind: CodeDocument.Row.Kind) -> NSColor? {
            switch kind {
            case .added: .systemGreen.withAlphaComponent(0.14)
            case .removed: .systemRed.withAlphaComponent(0.14)
            case .hunkHeader, .gap: .quaternaryLabelColor.withAlphaComponent(0.12)
            case .filler: .quaternaryLabelColor.withAlphaComponent(0.05)
            case .fileHeader: .controlAccentColor.withAlphaComponent(0.12)
            case .context: nil
            }
        }

        /// The gutter's +/− mark, so a change never relies on colour alone.
        static func markColor(for kind: CodeDocument.Row.Kind) -> NSColor {
            switch kind {
            case .added: .systemGreen
            case .removed: .systemRed
            case .hunkHeader, .context, .gap, .filler, .fileHeader: .tertiaryLabelColor
            }
        }

        static let hunkHeaderText = NSColor.secondaryLabelColor
        /// A file's heading in the all-files view: the code font, bold.
        static var fileHeaderFont: NSFont {
            NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold)
        }
        static let fileHeaderText = NSColor.labelColor
        static let lineNumber = NSColor.tertiaryLabelColor
        static let gutterBackground = NSColor.textBackgroundColor
        static let gutterSeparator = NSColor.separatorColor
    }
}
