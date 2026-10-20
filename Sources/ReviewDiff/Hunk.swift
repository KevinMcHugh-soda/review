/// One `@@ -a,b +c,d @@` block.
public struct Hunk: Hashable, Sendable {
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    /// What git prints after the closing `@@` — usually the enclosing
    /// function's signature. Empty when there is none.
    public let section: String
    public let lines: [DiffLine]

    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, section: String, lines: [DiffLine]) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.section = section
        self.lines = lines
    }

    /// The header as git prints it, with counts of 1 written out.
    public var header: String {
        let range = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        return section.isEmpty ? range : "\(range) \(section)"
    }
}
