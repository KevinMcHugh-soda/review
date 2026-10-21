/// A block of GitHub-flavoured Markdown, parsed far enough to lay out
/// natively. Text inside a block is still inline Markdown — emphasis, `code`,
/// links — for `AttributedString` to read, with GitHub's extras (reference
/// links, a few inline HTML tags) already rewritten into forms it knows.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(String)
    /// `---`, which gopls puts between a signature and its doc comment.
    case rule
    case list([MarkdownListItem])
    case table(MarkdownTable)
    case quote([MarkdownBlock])
    /// `<details>`: a summary line, and what it hides until opened.
    case details(summary: String, blocks: [MarkdownBlock])
}

public struct MarkdownListItem: Equatable, Sendable {
    public enum Marker: Equatable, Sendable {
        case bullet
        case number(Int)
        /// `- [ ]` and `- [x]`.
        case task(isDone: Bool)
    }

    public let marker: Marker
    /// The item's own text, then anything nested under it.
    public let blocks: [MarkdownBlock]

    public init(marker: Marker, blocks: [MarkdownBlock]) {
        self.marker = marker
        self.blocks = blocks
    }
}

public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable {
        case leading
        case center
        case trailing
    }

    public let alignments: [Alignment]
    public let header: [String]
    /// Each row has exactly as many cells as the header, as GitHub pads or
    /// cuts them.
    public let rows: [[String]]

    public init(alignments: [Alignment], header: [String], rows: [[String]]) {
        self.alignments = alignments
        self.header = header
        self.rows = rows
    }
}
