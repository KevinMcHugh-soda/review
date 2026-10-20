import ReviewDiff
import ReviewSyntax

/// Exactly what the code viewer draws: rows of text, each marked and
/// numbered, with highlight spans relative to the row.
///
/// Built here rather than in the view so the viewer stays a dumb renderer and
/// every decision about what a row is can be tested without AppKit.
public struct CodeDocument: Sendable {
    public struct Row: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            case hunkHeader
            case context
            case added
            case removed
        }

        public let kind: Kind
        public let text: String
        public let oldLine: Int?
        public let newLine: Int?
        public let spans: [HighlightSpan]
    }

    public enum Mode: String, Sendable, Hashable, CaseIterable {
        /// Hunks only, removed and added lines interleaved. The default.
        case diff
        /// The whole file as it is at head, with the PR's additions marked.
        case file
    }

    public let rows: [Row]
    /// The file has no text to show: binary, or empty on both sides.
    public let isBinary: Bool

    /// The widest line number in either column, for sizing the gutter.
    public var maxLineNumber: Int {
        rows.lazy.map { max($0.oldLine ?? 0, $0.newLine ?? 0) }.max() ?? 0
    }

    /// - Parameters:
    ///   - oldText: the file at the merge base; nil if it did not exist.
    ///   - newText: the file at head; nil if it was deleted.
    public init(file: FileDiff, oldText: String?, newText: String?, mode: Mode) {
        isBinary = file.isBinary
        guard !file.isBinary else {
            rows = []
            return
        }
        let language = SyntaxLanguage(path: file.path)
        // Each side is highlighted whole: a hunk alone starts mid-string or
        // mid-comment as often as not and would colour wrongly.
        let old = oldText.map { HighlightedLines.highlighting($0, as: language) }
        let new = newText.map { HighlightedLines.highlighting($0, as: language) }

        switch mode {
        case .diff:
            rows = Self.diffRows(file, old: old, new: new)
        case .file:
            rows = Self.fileRows(file, oldText: oldText, newText: newText, old: old, new: new)
        }
    }

    static func diffRows(_ file: FileDiff, old: HighlightedLines?, new: HighlightedLines?) -> [Row] {
        file.hunks.flatMap { hunk in
            let header = Row(kind: .hunkHeader, text: hunk.header, oldLine: nil, newLine: nil, spans: [])
            return [header] + hunk.lines.map { line in
                let spans =
                    if let newLine = line.newLine { new?.spans(onLine: newLine) ?? [] }
                    else if let oldLine = line.oldLine { old?.spans(onLine: oldLine) ?? [] }
                    else { [HighlightSpan]() }
                let kind: Row.Kind =
                    switch line.kind {
                    case .context: .context
                    case .added: .added
                    case .removed: .removed
                    }
                return Row(kind: kind, text: line.text, oldLine: line.oldLine, newLine: line.newLine, spans: spans)
            }
        }
    }

    /// Every line at head, marking those the PR added. A deleted file shows its
    /// old text, all removed.
    static func fileRows(
        _ file: FileDiff,
        oldText: String?,
        newText: String?,
        old: HighlightedLines?,
        new: HighlightedLines?
    ) -> [Row] {
        guard let newText else {
            return lines(of: oldText ?? "").enumerated().map { offset, text in
                Row(kind: .removed, text: text, oldLine: offset + 1, newLine: nil, spans: old?.spans(onLine: offset + 1) ?? [])
            }
        }
        let added = Set(file.hunks.flatMap(\.lines).filter { $0.kind == .added }.compactMap(\.newLine))
        return lines(of: newText).enumerated().map { offset, text in
            let number = offset + 1
            let isAdded = added.contains(number)
            return Row(
                kind: isAdded ? .added : .context,
                text: text,
                oldLine: isAdded ? nil : oldLine(forUnchanged: number, in: file.hunks),
                newLine: number,
                spans: new?.spans(onLine: number) ?? []
            )
        }
    }

    /// The merge-base line number of a head line the PR did not add.
    ///
    /// Inside a hunk the diff says; between hunks the offset is whatever the
    /// last hunk left behind. A range with a count of zero names the line
    /// *before* it (`+4,0` is "after line 4"), so its end is start + 1.
    static func oldLine(forUnchanged line: Int, in hunks: [Hunk]) -> Int {
        var delta = 0
        for hunk in hunks {
            let newEnd = hunk.newCount == 0 ? hunk.newStart + 1 : hunk.newStart + hunk.newCount
            if line < newEnd {
                if let paired = hunk.lines.first(where: { $0.newLine == line })?.oldLine { return paired }
                break
            }
            let oldEnd = hunk.oldCount == 0 ? hunk.oldStart + 1 : hunk.oldStart + hunk.oldCount
            delta = oldEnd - newEnd
        }
        return line + delta
    }

    /// Lines as git counts them: split on `\n`, no phantom empty last line.
    static func lines(of text: String) -> [String] {
        var lines = text.utf8
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}
