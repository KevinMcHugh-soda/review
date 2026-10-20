/// One file's worth of a unified diff.
public struct FileDiff: Hashable, Sendable {
    /// The path at the merge base; nil for an added file.
    public let oldPath: String?
    /// The path at head; nil for a deleted file.
    public let newPath: String?
    public let isBinary: Bool
    /// Only the mode changed (e.g. a script made executable).
    public let oldMode: String?
    public let newMode: String?
    /// Rename similarity as git reports it, 0–100.
    public let similarity: Int?
    /// The blob ids from the `index` line — full ids, because the diff is
    /// asked for with `--full-index`. Nil for a pure rename, which has no
    /// `index` line, and for the missing side of an add or delete.
    public let oldBlob: String?
    public let newBlob: String?
    public let hunks: [Hunk]

    public init(
        oldPath: String?,
        newPath: String?,
        isBinary: Bool = false,
        oldMode: String? = nil,
        newMode: String? = nil,
        similarity: Int? = nil,
        oldBlob: String? = nil,
        newBlob: String? = nil,
        hunks: [Hunk]
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.isBinary = isBinary
        self.oldMode = oldMode
        self.newMode = newMode
        self.similarity = similarity
        self.oldBlob = oldBlob
        self.newBlob = newBlob
        self.hunks = hunks
    }

    public enum Status: String, Hashable, Sendable {
        case added, deleted, renamed, modified
    }

    public var status: Status {
        switch (oldPath, newPath) {
        case (nil, _): .added
        case (_, nil): .deleted
        case let (old?, new?) where old != new: .renamed
        default: .modified
        }
    }

    /// The name to show: where the file is now, or where it was if deleted.
    public var path: String { newPath ?? oldPath ?? "" }

    public var additions: Int {
        hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .added } }
    }

    public var deletions: Int {
        hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .removed } }
    }
}

extension FileDiff: Identifiable {
    public var id: String { path }
}
