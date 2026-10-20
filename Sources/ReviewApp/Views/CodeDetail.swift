import ReviewDiff
import ReviewKit
import SwiftUI

/// The code viewer, with navigation results below it, a status line, and the
/// Diff/File switch and Back/Forward in the toolbar.
struct CodeDetail: View {
    @Bindable var session: ReviewSession
    @State private var resultsHeight = Theme.resultsIdealHeight
    @State private var dragStartHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            if session.selectedFile != nil || session.externalFile != nil {
                FileHeader(session: session)
                Divider()
            }
            if session.document?.source == .afterMerge {
                AfterMergeBanner(baseName: session.review?.pullRequest.base.name ?? "the base")
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let results = session.results {
                SplitDivider(isDragging: dragStartHeight != nil)
                    .gesture(resize)
                ResultsPanel(session: session, results: results)
                    .frame(height: resultsHeight)
            }
            if session.review != nil {
                Divider()
                NavigationStatusBar(session: session)
            }
        }
        .task(id: session.documentKey) { await session.loadDocument() }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Back", systemImage: "chevron.left") { session.goBack() }
                    .disabled(!session.canGoBack)
                    .help("Back (⌃⌘←)")
                Button("Forward", systemImage: "chevron.right") { session.goForward() }
                    .disabled(!session.canGoForward)
                    .help("Forward (⌃⌘→)")
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $session.mode) {
                    Text("Diff").tag(CodeDocument.Mode.diff)
                    Text("File").tag(CodeDocument.Mode.file)
                }
                .pickerStyle(.segmented)
                .help("Show only the changes (⌘1) or the whole file after the merge (⌘2)")
                .disabled(session.selectedFile == nil)
            }
        }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStartHeight ?? resultsHeight
                dragStartHeight = start
                // Dragging up grows the panel below.
                resultsHeight = min(Theme.resultsMaxHeight, max(Theme.resultsMinHeight, start - value.translation.height))
            }
            .onEnded { _ in dragStartHeight = nil }
    }

    @ViewBuilder
    private var content: some View {
        if session.review == nil {
            Color.clear
        } else if session.selectedFile == nil, session.externalFile == nil {
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
                    CodeView(
                        document: document,
                        documentID: id,
                        reveal: session.pendingReveal,
                        onCursorChange: { session.cursor = $0 },
                        onNavigate: { action, cursor in
                            Task { await session.perform(action, at: cursor) }
                        }
                    )
                }
            }
        }
    }

    /// Why a file with no rows is in the list at all.
    private var emptyDescription: String {
        guard let file = session.selectedFile else { return "The file is empty." }
        if let old = file.oldMode, let new = file.newMode, old != new {
            return "Only the file mode changed, from \(old) to \(new)."
        }
        if file.status == .renamed, let old = file.oldPath {
            return "Renamed from \(old) with no changes to its contents."
        }
        return "The file is empty."
    }
}
