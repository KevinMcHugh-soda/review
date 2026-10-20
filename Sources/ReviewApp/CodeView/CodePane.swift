import AppKit
import ReviewKit

/// One scrolling code view with its gutter, and the bookkeeping that decides
/// when to replace its text. `CodeView` uses one; `SplitCodeView` two.
@MainActor
final class CodePane: NSObject, NSTextViewDelegate {
    let scrollView = NSScrollView()
    let textView = CodeTextView.make()
    let gutter: LineNumberGutter

    private var shownID: String?
    private var shownScrollKey: String?
    private var revealedID: UUID?
    var onSelectionChange: ((Cursor, ClosedRange<Int>?) -> Void)?

    override init() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        gutter = LineNumberGutter(textView: textView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        super.init()
        textView.delegate = self
    }

    /// Shows `rows` if they are not already showing. `id` changes with
    /// anything that changes the text; `scrollKey` only with the file and
    /// mode, so expanding a gap keeps the place.
    func show(_ rows: [CodeDocument.Row], id: String, scrollKey: String) {
        guard shownID != id else { return }
        let keepScroll = shownScrollKey == scrollKey
        shownID = id
        shownScrollKey = scrollKey
        if !keepScroll { revealedID = nil }
        textView.show(rows, text: CodeAttributedText.make(rows), keepingScroll: keepScroll)
        gutter.update(rows: rows)
    }

    /// Scrolls to a reveal once per request.
    func apply(_ reveal: Reveal?, row: Int?) {
        guard let reveal, reveal.id != revealedID, let row else { return }
        revealedID = reveal.id
        // After this layout pass, once the new text is laid out.
        DispatchQueue.main.async { [textView] in
            textView.reveal(row: row, column: reveal.column, length: reveal.length)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let range = textView.selectedRange()
        guard let cursor = textView.cursor(at: range.location) else { return }
        let rows = textView.rows(in: range)
        // Deferred: this also fires while `updateNSView` replaces the text,
        // and changing observed state mid-update is not allowed.
        DispatchQueue.main.async { [onSelectionChange] in onSelectionChange?(cursor, rows) }
    }
}
