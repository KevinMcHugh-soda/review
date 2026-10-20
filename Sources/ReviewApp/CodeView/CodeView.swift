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

    final class Coordinator {
        var shownID: String?
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
        scrollView.documentView = textView

        let gutter = LineNumberGutter(textView: textView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard context.coordinator.shownID != documentID,
              let textView = scrollView.documentView as? CodeTextView
        else { return }
        context.coordinator.shownID = documentID
        textView.show(document.rows, text: CodeAttributedText.make(document))
        (scrollView.verticalRulerView as? LineNumberGutter)?.update(maxLineNumber: document.maxLineNumber)
    }
}
