import AppKit
import ReviewKit

/// A read-only NSTextView that draws full-width diff bands behind its rows.
///
/// TextKit 1, deliberately: the gutter and the bands need each row's line
/// fragment rect, which `NSLayoutManager` hands over directly, and a read-only
/// viewer gains nothing from TextKit 2's editing model. Non-contiguous layout
/// keeps large files fast.
final class CodeTextView: NSTextView {
    /// One kind per row, and the UTF-16 offset where each row starts.
    private(set) var rowKinds: [CodeDocument.Row.Kind] = []
    private(set) var rowStarts: [Int] = []
    private(set) var rows: [CodeDocument.Row] = []

    static func make() -> CodeTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        // Code does not wrap: one row is one line fragment, which the bands
        // and the gutter both rely on.
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)

        let view = CodeTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.autoresizingMask = [.width, .height]
        view.textContainerInset = Theme.Code.textInset
        view.backgroundColor = Theme.Code.background
        view.drawsBackground = true
        return view
    }

    func show(_ rows: [CodeDocument.Row], text: NSAttributedString) {
        self.rows = rows
        rowKinds = rows.map(\.kind)
        var starts: [Int] = []
        starts.reserveCapacity(rows.count)
        var offset = 0
        for row in rows {
            starts.append(offset)
            offset += (row.text as NSString).length + 1
        }
        rowStarts = starts
        textStorage?.setAttributedString(text)
        setSelectedRange(NSRange(location: 0, length: 0))
        scroll(.zero)
        needsDisplay = true
    }

    /// The row whose text contains a UTF-16 offset.
    func row(containing offset: Int) -> Int {
        var low = 0
        var high = rowStarts.count - 1
        guard high >= 0 else { return 0 }
        while low < high {
            let middle = (low + high + 1) / 2
            if rowStarts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Visible rows and their line rects, in this view's coordinates.
    func visibleRows(in rect: NSRect) -> [(row: Int, rect: NSRect)] {
        guard let layoutManager, let textContainer, !rowStarts.isEmpty else { return [] }
        let containerRect = rect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let length = textStorage?.length ?? 0

        var result: [(row: Int, rect: NSRect)] = []
        var row = self.row(containing: characters.location)
        while row < rowStarts.count, rowStarts[row] <= NSMaxRange(characters) {
            let start = rowStarts[row]
            var lineRect =
                if start < length {
                    layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
                } else {
                    // An empty final row has no glyph; it lives in the extra fragment.
                    layoutManager.extraLineFragmentRect
                }
            lineRect.origin.y += textContainerOrigin.y
            result.append((row, lineRect))
            row += 1
        }
        return result
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        for (row, lineRect) in visibleRows(in: rect) {
            guard let band = Theme.Code.band(for: rowKinds[row]) else { continue }
            band.setFill()
            NSRect(x: rect.minX, y: lineRect.minY, width: rect.width, height: lineRect.height).fill()
        }
    }
}
