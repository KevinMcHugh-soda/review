import ReviewCore
import ReviewDiff

extension FileDiff {
    /// What "viewed" is pinned to: the head blob, so a push that changes the
    /// file unmarks it and one that does not leaves it marked. A deleted file
    /// is pinned to its old blob; a pure rename (no `index` line) to the head
    /// commit, which unmarks it on any push.
    public func viewedKey(headSHA: String) -> String {
        newBlob ?? (newPath == nil ? oldBlob.map { "deleted:\($0)" } : nil) ?? "commit:\(headSHA)"
    }
}

extension ReviewNotes {
    public func isViewed(_ file: FileDiff, headSHA: String) -> Bool {
        viewed[file.path] == file.viewedKey(headSHA: headSHA)
    }

    public mutating func setViewed(_ isViewed: Bool, _ file: FileDiff, headSHA: String) {
        viewed[file.path] = isViewed ? file.viewedKey(headSHA: headSHA) : nil
    }

    /// Notes that the reviewer has opened the PR at `head`. A head they have
    /// not seen before becomes the latest, and the one they had seen becomes
    /// what "changes since last viewed" compares against — until the next
    /// push, so reopening the same head keeps the comparison.
    public mutating func recordView(ofHead head: String) {
        guard head != viewedHead else { return }
        if viewedHead != nil { previousViewedHead = viewedHead }
        viewedHead = head
    }
}
