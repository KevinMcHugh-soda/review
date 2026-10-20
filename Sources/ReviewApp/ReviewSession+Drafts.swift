import Foundation
import ReviewClaude
import ReviewCore
import ReviewDiff
import ReviewKit

extension ReviewSession {
    // MARK: Storage

    func loadNotes() {
        guard let notesStore else { return }
        do {
            notes = try notesStore.load(reference)
            // A PR you have already marked up opens with your drafts showing.
            if !notes.drafts.isEmpty { isInspectorShown = true }
        } catch {
            navigationMessage = "Your drafts could not be read: \(error)"
        }
    }

    /// Saves shortly after the last change, so typing does not write a file
    /// per keystroke.
    func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            saveNotesNow()
        }
    }

    func saveNotesNow() {
        pendingSave?.cancel()
        do {
            try notesStore?.save(notes, for: reference)
        } catch {
            navigationMessage = "Your drafts could not be saved: \(error)"
        }
    }

    // MARK: Drafts

    var sortedDrafts: [DraftComment] {
        notes.drafts.sorted { ($0.anchor.path, $0.anchor.startLine) < ($1.anchor.path, $1.anchor.startLine) }
    }

    func draft(_ id: UUID) -> DraftComment? {
        notes.drafts.first { $0.id == id }
    }

    private func updateDraft(_ id: UUID, _ change: (inout DraftComment) -> Void) {
        guard let index = notes.drafts.firstIndex(where: { $0.id == id }) else { return }
        change(&notes.drafts[index])
        notes.drafts[index].updatedAt = .now
        scheduleSave()
    }

    func setBody(_ body: String, of id: UUID) {
        updateDraft(id) { $0.body = body }
    }

    func deleteDraft(_ id: UUID) {
        askTasks[id]?.cancel()
        notes.drafts.removeAll { $0.id == id }
        if selectedDraftID == id { selectedDraftID = nil }
        scheduleSave()
    }

    /// Why Add Comment cannot act on the current selection, or nil if it can.
    var addCommentProblem: String? {
        guard let document else { return "Open a file first." }
        if document.source == .afterMerge { return "Comment in Diff view (⌘1): after-merge line numbers are not the PR's." }
        guard let rows = selectedRows ?? cursor.map({ $0.row...$0.row }) else { return "Select the lines to comment on." }
        if rows.allSatisfy({ document.rows.indices.contains($0) && document.rows[$0].kind == .hunkHeader }) {
            return "Select code lines, not a hunk header."
        }
        return nil
    }

    /// A draft on the selected lines. Lines with a head-side number anchor
    /// on head; a selection of only removed lines anchors on the base.
    func addDraft() {
        if let problem = addCommentProblem {
            navigationMessage = problem
            return
        }
        guard let document, let review, let rows = selectedRows ?? cursor.map({ $0.row...$0.row }) else { return }
        let selected = rows.filter { document.rows.indices.contains($0) }.map { document.rows[$0] }.filter { $0.kind != .hunkHeader }
        let headLines = selected.compactMap(\.newLine)
        let side: Side = headLines.isEmpty ? .base : .head
        let lines = side == .head ? headLines : selected.compactMap(\.oldLine)
        guard let first = lines.min(), let last = lines.max() else { return }
        let quoted = selected.filter { side == .head ? $0.newLine != nil : $0.oldLine != nil }.map(\.text)

        let path: String
        let isInPullRequest: Bool
        if let externalFile {
            path = displayPath(for: externalFile)
            isInPullRequest = false
        } else if let file = selectedFile, let name = side == .head ? file.newPath : file.oldPath {
            path = name
            isInPullRequest = true
        } else {
            return
        }
        let anchor = CommentAnchor(
            path: path, side: side, startLine: first, endLine: last,
            commit: side == .head ? review.pullRequest.head.sha : review.mergeBase,
            quotedLines: quoted, isInPullRequest: isInPullRequest
        )
        let draft = DraftComment(anchor: anchor)
        notes.drafts.append(draft)
        selectedDraftID = draft.id
        isInspectorShown = true
        scheduleSave()
    }

    /// Rows in the current document that a draft covers, and which draft.
    var draftRows: [Int: UUID] {
        guard let document else { return [:] }
        var rows: [Int: UUID] = [:]
        for draft in notes.drafts {
            let anchor = draft.anchor
            let matchesFile: Bool =
                if let externalFile { displayPath(for: externalFile) == anchor.path && anchor.side == .head }
                else if let file = selectedFile { (anchor.side == .head ? file.newPath : file.oldPath) == anchor.path }
                else { false }
            guard matchesFile, document.source != .afterMerge || anchor.side == .base else { continue }
            for (index, row) in document.rows.enumerated() {
                let line = anchor.side == .head ? row.newLine : (row.kind == .added ? nil : row.oldLine)
                if let line, anchor.lines.contains(line) { rows[index] = draft.id }
            }
        }
        return rows
    }

    /// Written against a head the PR has since moved past.
    func isStale(_ draft: DraftComment) -> Bool {
        guard let review else { return false }
        return draft.anchor.side == .head && draft.anchor.commit != review.pullRequest.head.sha
    }

    /// Shows a draft's lines in the viewer.
    func reveal(_ draft: DraftComment) {
        selectedDraftID = draft.id
        let anchor = draft.anchor
        if anchor.side == .base, let file = files.first(where: { $0.oldPath == anchor.path }) {
            // Base lines exist only in the diff's removed and context rows.
            mode = .diff
            selectedFilePath = file.path
            return
        }
        let url = anchor.path.hasPrefix("/") ? URL(fileURLWithPath: anchor.path) : worktree?.appendingPathComponent(anchor.path)
        guard let url else { return }
        open(CodeLocation(file: url, line: anchor.startLine, column: 0))
    }

    /// For launch options: selects head-side lines, adds a draft with a note,
    /// and optionally asks Claude and waits for the answer.
    func scriptedComment(lines: ClosedRange<Int>, note: String, ask shouldAsk: Bool) async {
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline, document?.row(forNewLine: lines.lowerBound) == nil || worktree == nil {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard let document, let first = document.row(forNewLine: lines.lowerBound),
              let last = document.row(forNewLine: lines.upperBound)
        else { return }
        selectedRows = first...last
        addDraft()
        guard let id = selectedDraftID else { return }
        setBody(note, of: id)
        guard shouldAsk else { return }
        ask(about: id)
        await askTasks[id]?.value
    }

    // MARK: Asking Claude

    var canAsk: Bool { assistant != nil && worktree != nil && review != nil }

    /// Why asking is not possible right now, or nil.
    var askProblem: String? {
        if assistant == nil { return "claude is not installed — see the tool status in the sidebar." }
        if worktree == nil { return "Waiting for the checkout." }
        return nil
    }

    /// Asks about a draft: the first time with its code and note, after that
    /// with whatever follow-up is typed.
    func ask(about id: UUID) {
        guard askTasks[id] == nil, let draft = draft(id) else { return }
        if let problem = askProblem {
            navigationMessage = problem
            return
        }
        guard let assistant, let review, let worktree else { return }
        let followUp = followUps[id]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let isFirst = draft.claudeSessionID == nil
        let question = followUp ?? (draft.body.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "What does this code do?")
        if !isFirst, followUp == nil { return }

        updateDraft(id) { $0.conversation.append(ConversationTurn(author: .reviewer, text: question)) }
        followUps[id] = nil
        asks[id] = AskProgress()
        askTasks[id] = Task {
            await run(id) {
                try await assistant.ask(about: draft, followUp: followUp, in: review, worktree: worktree)
            } finish: { result in
                self.updateDraft(id) { draft in
                    draft.conversation.append(Self.turn(for: result))
                    if !result.sessionID.isEmpty { draft.claudeSessionID = result.sessionID }
                }
            } fail: { message in
                self.updateDraft(id) { $0.conversation.append(ConversationTurn(author: .claude, text: message, isError: true)) }
            }
        }
    }

    /// Every draft in one prompt; follow-ups continue that conversation.
    func askAboutAll() {
        guard askTasks[overviewID] == nil else { return }
        if let problem = askProblem {
            navigationMessage = problem
            return
        }
        guard let assistant, let review, let worktree, !notes.drafts.isEmpty else { return }
        let followUp = followUps[overviewID]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let session = notes.overviewSessionID
        if session != nil, followUp == nil { return }
        let drafts = sortedDrafts
        notes.overview.append(ConversationTurn(
            author: .reviewer,
            text: followUp ?? "Go through all \(drafts.count == 1 ? "1 draft" : "\(drafts.count) drafts")."
        ))
        followUps[overviewID] = nil
        asks[overviewID] = AskProgress()
        scheduleSave()
        askTasks[overviewID] = Task {
            await run(overviewID) {
                try await assistant.askAboutAll(
                    drafts, followUp: session == nil ? nil : followUp, sessionID: session, in: review, worktree: worktree
                )
            } finish: { result in
                self.notes.overview.append(Self.turn(for: result))
                if !result.sessionID.isEmpty { self.notes.overviewSessionID = result.sessionID }
                self.scheduleSave()
            } fail: { message in
                self.notes.overview.append(ConversationTurn(author: .claude, text: message, isError: true))
                self.scheduleSave()
            }
        }
    }

    func cancelAsk(_ id: UUID) {
        askTasks[id]?.cancel()
    }

    /// Streams one turn into `asks[id]`, then hands the result on.
    private func run(
        _ id: UUID,
        start: () async throws -> AsyncThrowingStream<ClaudeEvent, any Error>,
        finish: (ClaudeResult) -> Void,
        fail: (String) -> Void
    ) async {
        defer {
            asks[id] = nil
            askTasks[id] = nil
        }
        do {
            for try await event in try await start() {
                switch event {
                case .text(let text):
                    asks[id]?.text += text
                    asks[id]?.activity = nil
                case .messageBoundary:
                    if let text = asks[id]?.text, !text.isEmpty, !text.hasSuffix("\n\n") { asks[id]?.text += "\n\n" }
                case .activity(let activity):
                    asks[id]?.activity = activity
                case .started:
                    break
                case .finished(let result):
                    finish(result)
                    return
                }
            }
            if Task.isCancelled { fail("Stopped.") }
        } catch is CancellationError {
            fail("Stopped.")
        } catch {
            fail(Task.isCancelled ? "Stopped." : "\(error)")
        }
    }

    private static func turn(for result: ClaudeResult) -> ConversationTurn {
        var text = result.text
        if !result.deniedTools.isEmpty {
            text += "\n\n_(Refused: \(result.deniedTools.joined(separator: ", ")) outside the checkout.)_"
        }
        return ConversationTurn(author: .claude, text: text, costUSD: result.costUSD, isError: result.isError)
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
