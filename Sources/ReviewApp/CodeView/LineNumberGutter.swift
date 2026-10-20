import AppKit
import ReviewKit

/// Two line-number columns — merge base, then head — and a +/− mark, as a
/// vertical ruler on the code's scroll view.
final class LineNumberGutter: NSRulerView {
    /// Which number columns to draw. A split pane needs one: the left only
    /// has base lines, the right only head lines.
    struct Columns: Equatable {
        var old = true
        var new = true
    }

    private var digits = 1
    private var columns = Columns()
    /// Clicking a row's draft bubble.
    var onSelectDraft: ((UUID) -> Void)?
    /// Clicking a row's GitHub thread mark.
    var onSelectThread: ((String) -> Void)?
    private static let bubble = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "Draft comment")
    private static let thread = NSImage(
        systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: "Comment on GitHub"
    )

    init(textView: CodeTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Resizes for the widest line number and the columns these rows use.
    func update(rows: [CodeDocument.Row]) {
        let maxLine = rows.lazy.map { max($0.oldLine ?? 0, $0.newLine ?? 0) }.max() ?? 0
        digits = max(String(maxLine).count, 2)
        columns = Columns(old: rows.contains { $0.oldLine != nil }, new: rows.contains { $0.newLine != nil })
        if !columns.old, !columns.new { columns = Columns() }
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: Theme.Code.gutterFont]).width
        let column = digitWidth * CGFloat(digits)
        let shown = CGFloat((columns.old ? 1 : 0) + (columns.new ? 1 : 0))
        ruleThickness = Theme.Code.draftMarkWidth + Theme.Code.gutterPadding * 2 + column * shown
            + Theme.Code.gutterColumnGap * shown + digitWidth
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        Theme.Code.gutterBackground.setFill()
        bounds.fill()
        Theme.Code.gutterSeparator.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        guard let textView = clientView as? CodeTextView else { return }
        let font = Theme.Code.gutterFont
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        let column = digitWidth * CGFloat(digits)
        let oldRight = Theme.Code.draftMarkWidth + Theme.Code.gutterPadding + (columns.old ? column : 0)
        let newRight = oldRight + (columns.old ? Theme.Code.gutterColumnGap : 0) + (columns.new ? column : 0)
        let markLeft = newRight + Theme.Code.gutterColumnGap

        // Numbers sit on the code's baseline, not centred in the row: the gutter
        // font is smaller, and a centred number reads as misaligned.
        let codeAscender = textView.layoutManager?.defaultBaselineOffset(for: Theme.Code.font) ?? Theme.Code.font.ascender
        let numberAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.Code.lineNumber]
        for (row, lineRect) in textView.visibleRows(in: textView.visibleRect) {
            let item = textView.rows[row]
            let y = convert(NSPoint(x: 0, y: lineRect.minY), from: textView).y
            let height = lineRect.height
            // `draw(at:)` in a flipped view takes the text's top-left corner.
            let top = y + codeAscender - font.ascender

            if let band = Theme.Code.band(for: item.kind) {
                band.setFill()
                NSRect(x: 0, y: y, width: bounds.width - 1, height: height).fill()
            }
            // A draft of yours outranks a thread on GitHub for the one slot.
            let badge: (NSImage?, NSColor)? =
                if textView.draftRows[row] != nil { (Self.bubble, Theme.Code.draftMark) }
                else if textView.threadRows[row] != nil { (Self.thread, Theme.Code.threadMark) }
                else { nil }
            if let (image, color) = badge, let image {
                let size = min(Theme.Code.draftMarkWidth - 4, height - 2)
                let rect = NSRect(x: 3, y: y + (height - size) / 2, width: size, height: size)
                image.withSymbolConfiguration(.init(paletteColors: [color]))?
                    .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            if columns.old { draw(item.oldLine, rightEdge: oldRight, y: top, attributes: numberAttributes) }
            if columns.new { draw(item.newLine, rightEdge: newRight, y: top, attributes: numberAttributes) }

            let mark =
                switch item.kind {
                case .added: "+"
                case .removed: "−"
                case .context, .hunkHeader, .gap, .filler: ""
                }
            (mark as NSString).draw(
                at: NSPoint(x: markLeft, y: top),
                withAttributes: [.font: font, .foregroundColor: Theme.Code.markColor(for: item.kind)]
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let textView = clientView as? CodeTextView else { return }
        let point = convert(event.locationInWindow, from: nil)
        let hit = textView.visibleRows(in: textView.visibleRect).first { _, lineRect in
            let y = convert(NSPoint(x: 0, y: lineRect.minY), from: textView).y
            return point.y >= y && point.y < y + lineRect.height
        }
        guard let hit else { return }
        if let draft = textView.draftRows[hit.row] {
            onSelectDraft?(draft)
        } else if let thread = textView.threadRows[hit.row] {
            onSelectThread?(thread)
        }
    }

    private func draw(_ number: Int?, rightEdge: CGFloat, y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        guard let number else { return }
        let text = String(number) as NSString
        let width = text.size(withAttributes: attributes).width
        text.draw(at: NSPoint(x: rightEdge - width, y: y), withAttributes: attributes)
    }
}
