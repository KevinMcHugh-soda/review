/// One line inside a hunk, with its line number on each side it exists on.
public struct DiffLine: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case context, added, removed
    }

    public let kind: Kind
    /// The line's text, without the leading ` `/`+`/`-` or the newline.
    public let text: String
    /// 1-based line number at the merge base; nil for an added line.
    public let oldLine: Int?
    /// 1-based line number at head; nil for a removed line.
    public let newLine: Int?
    /// git's `\ No newline at end of file` followed this line.
    public let isMissingNewline: Bool

    public init(kind: Kind, text: String, oldLine: Int?, newLine: Int?, isMissingNewline: Bool = false) {
        self.kind = kind
        self.text = text
        self.oldLine = oldLine
        self.newLine = newLine
        self.isMissingNewline = isMissingNewline
    }

    func missingNewline() -> Self {
        Self(kind: kind, text: text, oldLine: oldLine, newLine: newLine, isMissingNewline: true)
    }
}
