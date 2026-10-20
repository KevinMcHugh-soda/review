import AppKit
import ReviewKit
import SwiftUI

/// The code viewer: a `CodeTextView` in a scroll view, with the line-number
/// gutter as its ruler.
///
/// `documentID` decides when the text is replaced. SwiftUI calls
/// `updateNSView` for many reasons; re-setting the text each time would throw
/// away the scroll position and selection.
struct CodeView: NSViewRepresentable {
    let document: CodeDocument
    let documentID: String
    /// A place to scroll to once this document shows; applied once per id.
    let reveal: Reveal?
    let onCursorChange: (Cursor) -> Void
    let onNavigate: (NavigationAction, Cursor) -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var shownID: String?
        var revealedID: UUID?
        var onCursorChange: ((Cursor) -> Void)?

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CodeTextView,
                  let cursor = textView.cursor(at: textView.selectedRange().location)
            else { return }
            // Deferred: this also fires while `updateNSView` replaces the
            // text, and changing observed state mid-update is not allowed.
            DispatchQueue.main.async { [onCursorChange] in onCursorChange?(cursor) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = CodeTextView.make()
        textView.delegate = context.coordinator
        scrollView.documentView = textView

        let gutter = LineNumberGutter(textView: textView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        let coordinator = context.coordinator
        coordinator.onCursorChange = onCursorChange
        textView.onNavigate = { [onNavigate, weak textView] action, index in
            guard let cursor = textView?.cursor(at: index) else { return }
            onNavigate(action, cursor)
        }

        if coordinator.shownID != documentID {
            coordinator.shownID = documentID
            coordinator.revealedID = nil
            textView.show(document.rows, text: CodeAttributedText.make(document))
            (scrollView.verticalRulerView as? LineNumberGutter)?.update(maxLineNumber: document.maxLineNumber)
        }

        if let reveal, reveal.id != coordinator.revealedID, let row = document.row(forNewLine: reveal.line) {
            coordinator.revealedID = reveal.id
            // After this layout pass, once the new text is laid out.
            DispatchQueue.main.async {
                textView.reveal(row: row, column: reveal.column, length: reveal.length)
            }
        }
    }
}
