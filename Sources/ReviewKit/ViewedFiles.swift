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
}
