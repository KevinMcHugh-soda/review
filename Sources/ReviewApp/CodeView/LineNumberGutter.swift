import AppKit
import ReviewKit

/// Two line-number columns — merge base, then head — and a +/− mark, as a
/// vertical ruler on the code's scroll view.
final class LineNumberGutter: NSRulerView {
    private var digits = 1
    /// Clicking a row's draft bubble.
    var onSelectDraft: ((UUID) -> Void)?
    private static let bubble = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "Draft comment")

    init(textView: CodeTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Resizes for the widest line number in the document.
    func update(maxLineNumber: Int) {
        digits = max(String(maxLineNumber).count, 2)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: Theme.Code.gutterFont]).width
        let column = digitWidth * CGFloat(digits)
        ruleThickness = Theme.Code.draftMarkWidth + Theme.Code.gutterPadding * 2 + column * 2
            + Theme.Code.gutterColumnGap * 2 + digitWidth
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
        let oldRight = Theme.Code.draftMarkWidth + Theme.Code.gutterPadding + column
        let newRight = oldRight + Theme.Code.gutterColumnGap + column
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
            if textView.draftRows[row] != nil, let bubble = Self.bubble {
                let size = min(Theme.Code.draftMarkWidth - 4, height - 2)
                let rect = NSRect(x: 3, y: y + (height - size) / 2, width: size, height: size)
                bubble.withSymbolConfiguration(.init(paletteColors: [Theme.Code.draftMark]))?
                    .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            draw(item.oldLine, rightEdge: oldRight, y: top, attributes: numberAttributes)
            draw(item.newLine, rightEdge: newRight, y: top, attributes: numberAttributes)

            let mark =
                switch item.kind {
                case .added: "+"
                case .removed: "−"
                case .context, .hunkHeader: ""
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
        if let hit, let draft = textView.draftRows[hit.row] {
            onSelectDraft?(draft)
        }
    }

    private func draw(_ number: Int?, rightEdge: CGFloat, y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        guard let number else { return }
        let text = String(number) as NSString
        let width = text.size(withAttributes: attributes).width
        text.draw(at: NSPoint(x: rightEdge - width, y: y), withAttributes: attributes)
    }
}
