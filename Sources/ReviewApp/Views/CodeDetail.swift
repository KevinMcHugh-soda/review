import ReviewDiff
import ReviewKit
import SwiftUI

/// The selected file in the code viewer, with the Diff/File switch in the
/// toolbar.
struct CodeDetail: View {
    @Bindable var session: ReviewSession

    var body: some View {
        content
            .task(id: session.documentKey) { await session.loadDocument() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("View", selection: $session.mode) {
                        Text("Diff").tag(CodeDocument.Mode.diff)
                        Text("File").tag(CodeDocument.Mode.file)
                    }
                    .pickerStyle(.segmented)
                    .help("Show only the changes (⌘1) or the whole file (⌘2)")
                    .disabled(session.selectedFile == nil)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if session.review == nil {
            Color.clear
        } else if session.selectedFile == nil {
            ContentUnavailableView("No File Selected", systemImage: "doc.text")
        } else {
            switch session.documentState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't Show This File", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message).textSelection(.enabled)
                }
            case .loaded(let document, let id):
                if document.isBinary {
                    ContentUnavailableView("Binary File", systemImage: "doc.zipper", description: Text("There is no text to show."))
                } else if document.rows.isEmpty {
                    ContentUnavailableView(
                        "No Text Changes",
                        systemImage: "doc.text",
                        description: Text(emptyDescription)
                    )
                } else {
                    CodeView(document: document, documentID: id)
                }
            }
        }
    }

    /// Why a file with no rows is in the list at all.
    private var emptyDescription: String {
        guard let file = session.selectedFile else { return "" }
        if let old = file.oldMode, let new = file.newMode, old != new {
            return "Only the file mode changed, from \(old) to \(new)."
        }
        if file.status == .renamed, let old = file.oldPath {
            return "Renamed from \(old) with no changes to its contents."
        }
        return "The file is empty."
    }
}
