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
        .sheet(isPresented: $session.isPostSheetShown) {
            PostReviewSheet(session: session)
        }
        .inspector(isPresented: $session.isInspectorShown) {
            DraftsInspector(session: session)
                .inspectorColumnWidth(min: Theme.inspectorMinWidth, ideal: Theme.inspectorIdealWidth, max: Theme.inspectorMaxWidth)
        }
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
                    Text("Split").tag(CodeDocument.Mode.split)
                    Text("File").tag(CodeDocument.Mode.file)
                }
                .pickerStyle(.segmented)
                .help("The changes (⌘1), side by side (⌘2), or the whole file after the merge (⌘3)")
                .disabled(session.selectedFile == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $session.isContinuous) {
                    Label("All Files", systemImage: "rectangle.stack")
                }
                .help("Every file in one scroll, or one at a time (⌘4)")
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $session.isInspectorShown) {
                    Label("Drafts", systemImage: "text.bubble")
                }
                .help("Show your draft comments (⌥⌘0)")
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
                    if session.mode == .split, document.leftRows != nil {
                        SplitCodeView(
                            document: document, documentID: id, scrollKey: session.scrollKey ?? id,
                            reveal: session.pendingReveal, draftRows: session.draftRows,
                            threadRows: session.threadRows, actions: actions
                        )
                    } else {
                        CodeView(
                            document: document, documentID: id, scrollKey: session.scrollKey ?? id,
                            reveal: session.pendingReveal, draftRows: session.draftRows,
                            threadRows: session.threadRows, actions: actions
                        )
                    }
                }
            }
        }
    }

    private var actions: CodeViewActions {
        CodeViewActions(
            onSelectionChange: { cursor, rows in
                session.cursor = cursor
                session.selectedRows = rows
            },
            onNavigate: { action, cursor in
                Task { await session.perform(action, at: cursor) }
            },
            onAddComment: { session.addDraft() },
            onSelectDraft: { id in
                session.selectedDraftID = id
                session.isInspectorShown = true
            },
            onSelectThread: { id in
                session.selectedThreadID = id
                session.expand(threadID: id)
                session.isInspectorShown = true
            },
            onExpandGap: { session.expandGap(atRow: $0, lines: $1) },
            onHeaderClick: { session.toggleFile(atRow: $0) },
            onTopRowChange: { session.didScroll(toRow: $0) },
            onHover: { await session.hover(at: $0) }
        )
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
