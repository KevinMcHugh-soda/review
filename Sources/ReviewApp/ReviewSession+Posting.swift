import Foundation
import ReviewCore
import ReviewKit

extension ReviewSession {
    // MARK: Threads already on GitHub

    func loadThreads() async {
        guard let publisher, let review else { return }
        do {
            threads = try await publisher.threads(for: review)
            threadsError = nil
        } catch {
            threadsError = "\(error)"
        }
    }

    /// Rows in the current document with a current (not outdated) thread.
    var threadRows: [Int: String] {
        guard let document, document.source == .pullRequest, let file = selectedFile, externalFile == nil else { return [:] }
        var rows: [Int: String] = [:]
        for thread in threads where !thread.isOutdated {
            guard let lines = thread.lines,
                  (thread.side == .head ? file.newPath : file.oldPath) == thread.path
            else { continue }
            for (index, row) in document.rows.enumerated() {
                let line = thread.side == .head ? row.newLine : (row.kind == .added ? nil : row.oldLine)
                if let line, lines.contains(line) { rows[index] = thread.id }
            }
        }
        return rows
    }

    func reveal(_ thread: ReviewThread) {
        selectedThreadID = thread.id
        guard let line = thread.line ?? thread.originalLine else { return }
        if thread.side == .base, let file = files.first(where: { $0.oldPath == thread.path }) {
            mode = .diff
            selectedFilePath = file.path
            return
        }
        guard let worktree else { return }
        open(CodeLocation(file: worktree.appendingPathComponent(thread.path), line: line, column: 0))
    }

    // MARK: Drafts to post

    var unpostedDrafts: [DraftComment] { sortedDrafts.filter { $0.posted == nil } }
    var postedDrafts: [DraftComment] { sortedDrafts.filter { $0.posted != nil } }

    func setExcluded(_ isExcluded: Bool, _ id: UUID) {
        guard let index = notes.drafts.firstIndex(where: { $0.id == id }) else { return }
        notes.drafts[index].isExcludedFromReview = isExcluded
        scheduleSave()
    }

    /// Records a successful post on every draft that went out in it.
    func didPost(_ plan: ReviewPlan, url: URL?) {
        let posted = DraftComment.Posted(date: .now, reviewURL: url)
        for id in plan.postedDraftIDs {
            if let index = notes.drafts.firstIndex(where: { $0.id == id }) { notes.drafts[index].posted = posted }
        }
        saveNotesNow()
        Task { await loadThreads() }
    }
}
