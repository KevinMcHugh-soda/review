import AppKit
import ReviewKit

/// Turns a `CodeDocument` into the attributed string the text view shows:
/// rows joined by newlines, monospaced, with highlight spans coloured.
enum CodeAttributedText {
    static func make(_ rows: [CodeDocument.Row]) -> NSAttributedString {
        let font = Theme.Code.font
        let paragraph = NSMutableParagraphStyle()
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        paragraph.tabStops = []
        paragraph.defaultTabInterval = spaceWidth * CGFloat(Theme.Code.tabWidth)
        paragraph.lineSpacing = Theme.Code.lineSpacing

        let text = rows.map(\.text).joined(separator: "\n")
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: Theme.Code.text, .paragraphStyle: paragraph]
        )
        let length = result.length

        var offset = 0
        result.beginEditing()
        for row in rows {
            let rowLength = (row.text as NSString).length
            if row.kind == .hunkHeader || row.kind == .gap {
                result.addAttribute(
                    .foregroundColor, value: Theme.Code.hunkHeaderText,
                    range: NSRange(location: offset, length: rowLength)
                )
            }
            // Spans arrive in paint order; later ones overwrite earlier ones.
            for span in row.spans {
                let clipped = NSIntersectionRange(span.range, NSRange(location: 0, length: rowLength))
                guard clipped.length > 0, offset + NSMaxRange(clipped) <= length else { continue }
                result.addAttribute(
                    .foregroundColor, value: Theme.Code.color(for: span.kind),
                    range: NSRange(location: offset + clipped.location, length: clipped.length)
                )
            }
            offset += rowLength + 1
        }
        result.endEditing()
        return result
    }
}
