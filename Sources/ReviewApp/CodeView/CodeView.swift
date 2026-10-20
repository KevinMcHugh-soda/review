import AppKit
import ReviewKit
import SwiftUI

/// What the code view reports and asks for — the same for one pane or two.
struct CodeViewActions {
    let onSelectionChange: (Cursor, ClosedRange<Int>?) -> Void
    let onNavigate: (NavigationAction, Cursor) -> Void
    let onAddComment: () -> Void
    let onSelectDraft: (UUID) -> Void
    let onSelectThread: (String) -> Void
    let onExpandGap: (Int) -> Void
    let onHover: (Cursor) async -> String?
}

/// The code viewer: one `CodePane` showing a document's rows.
///
/// `documentID` decides when the text is replaced. SwiftUI calls
/// `updateNSView` for many reasons; re-setting the text each time would throw
/// away the scroll position and selection.
struct CodeView: NSViewRepresentable {
    let document: CodeDocument
    let documentID: String
    let scrollKey: String
    /// A place to scroll to once this document shows; applied once per id.
    let reveal: Reveal?
    let draftRows: [Int: UUID]
    let threadRows: [Int: String]
    let actions: CodeViewActions

    func makeCoordinator() -> CodePane {
        CodePane()
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let pane = context.coordinator
        pane.configureInteractive(actions)
        pane.show(document.rows, id: documentID, scrollKey: scrollKey)
        pane.textView.setMarks(drafts: draftRows, threads: threadRows)
        pane.apply(reveal, row: reveal?.row(in: document))
    }
}

extension CodePane {
    /// Wires a pane up for full interaction: navigation, comments, gaps, hover.
    func configureInteractive(_ actions: CodeViewActions) {
        onSelectionChange = actions.onSelectionChange
        textView.onNavigate = { [weak textView] action, index in
            guard let cursor = textView?.cursor(at: index) else { return }
            actions.onNavigate(action, cursor)
        }
        textView.onAddComment = actions.onAddComment
        textView.onExpandGap = actions.onExpandGap
        textView.onHover = { [weak textView] index in
            guard let cursor = textView?.cursor(at: index) else { return nil }
            return await actions.onHover(cursor)
        }
        gutter.onSelectDraft = actions.onSelectDraft
        gutter.onSelectThread = actions.onSelectThread
    }
}

extension CodeTextView {
    func setMarks(drafts: [Int: UUID], threads: [Int: String]) {
        if draftRows != drafts { draftRows = drafts }
        if threadRows != threads { threadRows = threads }
    }
}
