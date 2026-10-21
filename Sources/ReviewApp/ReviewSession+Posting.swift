import Foundation
import ReviewCore
import ReviewDiff
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
        guard let document, document.source == .pullRequest, externalFile == nil else { return [:] }
        let current = threads.filter { !$0.isOutdated && $0.lines != nil }
        guard !current.isEmpty else { return [:] }
        var rows: [Int: String] = [:]
        for (index, row) in document.rows.enumerated() where row.isCode && document.isNavigable(atRow: index) {
            guard let file = file(atRow: index) else { continue }
            for thread in current where (thread.side == .head ? file.newPath : file.oldPath) == thread.path {
                let line = thread.side == .head ? row.newLine : (row.kind == .added ? nil : row.oldLine)
                if let line, thread.lines?.contains(line) == true { rows[index] = thread.id }
            }
        }
        return rows
    }

    func isCollapsed(_ thread: ReviewThread) -> Bool {
        thread.isResolved != toggledThreads.contains(thread.id)
    }

    func toggleCollapsed(_ thread: ReviewThread) {
        if toggledThreads.contains(thread.id) {
            toggledThreads.remove(thread.id)
        } else {
            toggledThreads.insert(thread.id)
        }
    }

    /// Selecting a collapsed thread — from its marker in the code — opens it.
    func expand(threadID: String) {
        guard let thread = threads.first(where: { $0.id == threadID }), isCollapsed(thread) else { return }
        toggleCollapsed(thread)
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

extension ReviewSession {
    // MARK: Viewed files

    func isViewed(_ file: FileDiff) -> Bool {
        guard let review else { return false }
        return notes.isViewed(file, headSHA: review.pullRequest.head.sha)
    }

    func setViewed(_ isViewed: Bool, _ file: FileDiff) {
        guard let review else { return }
        notes.setViewed(isViewed, file, headSHA: review.pullRequest.head.sha)
        scheduleSave()
    }

    var viewedCount: Int { files.count { isViewed($0) } }

    /// Marks the selected file viewed and moves to the next unviewed one —
    /// the reviewer's main loop. On a viewed file, unmarks it instead.
    func toggleViewedAndAdvance() {
        guard let file = selectedFile else { return }
        if isViewed(file) {
            setViewed(false, file)
            return
        }
        setViewed(true, file)
        guard let index = files.firstIndex(of: file) else { return }
        let rest = files[(index + 1)...] + files[..<index]
        if let next = rest.first(where: { !isViewed($0) }) { selectedFilePath = next.path }
    }

    // MARK: Changes within a file

    /// The row each change starts on: the first row after each hunk header
    /// in Diff view, the first of each run of added lines in File view.
    var changeStarts: [Int] {
        guard let rows = document?.rows else { return [] }
        return rows.indices.compactMap { index in
            switch rows[index].kind {
            case .hunkHeader:
                rows.indices.contains(index + 1) ? index + 1 : nil
            case .added, .removed:
                mode == .file && (index == 0 || rows[index - 1].kind == .context) ? index : nil
            case .context, .gap, .filler, .fileHeader:
                nil
            }
        }
    }

    /// Moves to the next or previous change, staying put at either end.
    func revealChange(offset: Int) {
        let starts = changeStarts
        let current = cursor?.row ?? -1
        let target = offset > 0 ? starts.first { $0 > current } : starts.last { $0 < current }
        guard let target else { return }
        cursor = Cursor(row: target, column: 0)
        pendingReveal = Reveal(row: target)
    }
}

extension ReviewSession {
    // MARK: Replying to and resolving threads

    /// Posts a reply on GitHub — public at once — then reloads the threads.
    func reply(to thread: ReviewThread) async {
        let body = (threadReplies[thread.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let publisher, threadActions[thread.id] == nil else { return }
        threadActions[thread.id] = .replying
        defer { threadActions[thread.id] = nil }
        do {
            try await publisher.reply(to: thread, body: body)
            threadReplies[thread.id] = nil
            threadErrors[thread.id] = nil
            await loadThreads()
        } catch {
            threadErrors[thread.id] = "\(error)"
        }
    }

    func toggleResolved(_ thread: ReviewThread) async {
        guard let publisher, threadActions[thread.id] == nil else { return }
        threadActions[thread.id] = .resolving
        defer { threadActions[thread.id] = nil }
        do {
            try await publisher.setResolved(!thread.isResolved, thread)
            threadErrors[thread.id] = nil
            await loadThreads()
        } catch {
            threadErrors[thread.id] = "\(error)"
        }
    }
}
