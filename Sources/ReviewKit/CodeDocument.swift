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
            /// Unchanged lines the diff left out, collapsed into one row that
            /// expands when clicked.
            case gap
            /// The empty side of a split row: an added line has nothing on the
            /// left, a removed one nothing on the right.
            case filler
            /// The heading above each file when every file is shown in one
            /// scroll.
            case fileHeader
        }

        public let kind: Kind
        public let text: String
        public let oldLine: Int?
        public let newLine: Int?
        public let spans: [HighlightSpan]
        /// For a `.gap` row, which gap it is: 0 before the first hunk, `n`
        /// after the last of `n` hunks.
        public let gap: Int?
        /// For a `.gap` row, the head lines it stands for.
        public let gapLines: ClosedRange<Int>?
        /// Which of the PR's files the row belongs to, by index into
        /// `LoadedReview.files`. Set in the all-files document; nil in a
        /// single file's, where every row is the selected file's.
        public let file: Int?

        init(
            kind: Kind, text: String, oldLine: Int?, newLine: Int?, spans: [HighlightSpan],
            gap: Int? = nil, gapLines: ClosedRange<Int>? = nil, file: Int? = nil
        ) {
            self.kind = kind
            self.text = text
            self.oldLine = oldLine
            self.newLine = newLine
            self.spans = spans
            self.gap = gap
            self.gapLines = gapLines
            self.file = file
        }

        /// The same row, as part of file `index` in the all-files document.
        func inFile(_ index: Int) -> Row {
            Row(kind: kind, text: text, oldLine: oldLine, newLine: newLine, spans: spans,
                gap: gap, gapLines: gapLines, file: index)
        }

        /// A row that stands for code: not a header, gap or filler.
        public var isCode: Bool {
            switch kind {
            case .context, .added, .removed: true
            case .hunkHeader, .gap, .filler, .fileHeader: false
            }
        }
    }

    public enum Mode: String, Sendable, Hashable, CaseIterable {
        /// Hunks only, removed and added lines interleaved. The default.
        case diff
        /// Hunks side by side: the base on the left, head on the right.
        case split
        /// The whole file as it is at head, with the PR's additions marked.
        case file
    }

    /// Where the text came from, which decides whether navigation can work
    /// on it: the servers run on a checkout of the PR's head.
    public enum Source: Sendable, Hashable {
        /// The diff, or the file at head.
        case pullRequest
        /// The file as it will be after merging into a base that has moved,
        /// where it differs from head. Line numbers do not match the head
        /// checkout, so navigation is off.
        case afterMerge
        /// A file outside the PR's changes: a definition in another file, the
        /// standard library, the module cache.
        case other
    }

    /// In split mode, the right (head) side; otherwise every row.
    public let rows: [Row]
    /// In split mode, the left (base) side, row for row beside `rows`.
    public let leftRows: [Row]?
    /// The file has no text to show: binary, or empty on both sides.
    public let isBinary: Bool
    public private(set) var source: Source = .pullRequest

    public var isNavigable: Bool { source != .afterMerge }
    /// In the all-files document, the files showing after-merge text, whose
    /// line numbers do not match the head checkout.
    public private(set) var afterMergeFiles: Set<Int> = []

    /// Whether a row's line numbers are the PR head's, so navigation and
    /// comments can use them.
    public func isNavigable(atRow row: Int) -> Bool {
        guard isNavigable else { return false }
        guard let file = file(atRow: row) else { return true }
        return !afterMergeFiles.contains(file)
    }

    /// The widest line number in either column, for sizing the gutter.
    public var maxLineNumber: Int {
        rows.lazy.map { max($0.oldLine ?? 0, $0.newLine ?? 0) }.max() ?? 0
    }

    /// - Parameters:
    ///   - oldText: the file at the merge base; nil if it did not exist.
    ///   - newText: the file at head; nil if it was deleted.
    ///   - expandedGaps: which gaps between hunks to show in full.
    public init(file: FileDiff, oldText: String?, newText: String?, mode: Mode, expandedGaps: Set<Int> = []) {
        isBinary = file.isBinary
        guard !file.isBinary else {
            rows = []
            leftRows = nil
            return
        }
        let language = SyntaxLanguage(path: file.path)
        // Each side is highlighted whole: a hunk alone starts mid-string or
        // mid-comment as often as not and would colour wrongly.
        let old = oldText.map { HighlightedLines.highlighting($0, as: language) }
        let new = newText.map { HighlightedLines.highlighting($0, as: language) }

        let newLineCount = newText.map { Self.lines(of: $0).count } ?? 0
        let newLines = newText.map(Self.lines) ?? []
        switch mode {
        case .diff:
            rows = Self.diffRows(file, old: old, new: new, newLines: newLines, newLineCount: newLineCount, expanded: expandedGaps)
            leftRows = nil
        case .split:
            let split = Self.splitRows(
                file, old: old, new: new, newLines: newLines, newLineCount: newLineCount, expanded: expandedGaps
            )
            rows = split.right
            leftRows = split.left
        case .file:
            rows = Self.fileRows(file, oldText: oldText, newText: newText, old: old, new: new)
            leftRows = nil
        }
    }

    /// A file shown whole with nothing marked — one the PR does not change.
    public init(plainText text: String, path: String) {
        isBinary = false
        leftRows = nil
        source = .other
        let lines = HighlightedLines.highlighting(text, as: SyntaxLanguage(path: path))
        rows = Self.lines(of: text).enumerated().map { offset, line in
            Row(kind: .context, text: line, oldLine: nil, newLine: offset + 1, spans: lines.spans(onLine: offset + 1))
        }
    }

    func from(_ source: Source) -> Self {
        var copy = self
        copy.source = source
        return copy
    }

    /// The row showing a 1-based line at head (or in a plain file). In the
    /// all-files document, `file` says whose line.
    public func row(forNewLine line: Int, file: Int? = nil) -> Int? {
        rows.firstIndex { $0.newLine == line && (file == nil || $0.file == file) }
    }

    /// The header row of a file in the all-files document.
    public func headerRow(forFile file: Int) -> Int? {
        rows.firstIndex { $0.kind == .fileHeader && $0.file == file }
    }

    /// The collapsed gap that holds a head line, so a jump there can open it.
    public func gapRow(containing line: Int, file: Int? = nil) -> Int? {
        rows.firstIndex { $0.kind == .gap && $0.gapLines?.contains(line) == true && (file == nil || $0.file == file) }
    }

    /// The file a row belongs to: its own in the all-files document, found by
    /// walking up to the nearest row that knows.
    public func file(atRow row: Int) -> Int? {
        guard rows.indices.contains(row) else { return nil }
        return rows[row].file
    }

    /// Every file one after another, each under its header — GitHub's "Files
    /// changed" page. `documents[i]` is file `i`'s own document, or nil for a
    /// file shown only as its header (viewed and collapsed, or binary).
    public init(combining documents: [(header: String, document: CodeDocument?)]) {
        isBinary = false
        let isSplit = documents.contains { $0.document?.leftRows != nil }
        var rows: [Row] = []
        var left: [Row] = []
        for (index, item) in documents.enumerated() {
            let header = Row(kind: .fileHeader, text: item.header, oldLine: nil, newLine: nil, spans: [], file: index)
            rows.append(header)
            if isSplit { left.append(header) }
            guard let document = item.document else { continue }
            rows += document.rows.map { $0.inFile(index) }
            if isSplit {
                left += (document.leftRows ?? document.rows).map { $0.inFile(index) }
            }
        }
        self.rows = rows
        leftRows = isSplit ? left : nil
        afterMergeFiles = Set(documents.indices.filter { documents[$0].document?.source == .afterMerge })
    }

    static func diffRows(
        _ file: FileDiff, old: HighlightedLines?, new: HighlightedLines?,
        newLines: [String], newLineCount: Int, expanded: Set<Int>
    ) -> [Row] {
        let gaps = Self.gaps(in: file, newLineCount: newLineCount)
        var rows: [Row] = []
        for (index, hunk) in file.hunks.enumerated() {
            // Added and deleted files have no gaps at all.
            if gaps.indices.contains(index) {
                rows += gapRows(gaps[index], file: file, new: new, newLines: newLines, expanded: expanded)
            }
            rows.append(Row(kind: .hunkHeader, text: hunk.header, oldLine: nil, newLine: nil, spans: []))
            rows += hunk.lines.map { row(for: $0, old: old, new: new) }
        }
        if let trailing = gaps.last, gaps.count > file.hunks.count {
            rows += gapRows(trailing, file: file, new: new, newLines: newLines, expanded: expanded)
        }
        return rows
    }

    private static func row(for line: DiffLine, old: HighlightedLines?, new: HighlightedLines?) -> Row {
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

    /// A run of head lines the diff does not show.
    struct Gap: Hashable {
        let index: Int
        let lines: ClosedRange<Int>?
    }

    /// The gap before each hunk, and one after the last when the file goes on.
    /// Head-side line ranges; nil where hunks touch. A count of zero names the
    /// line *before* the range, so a hunk's first head line is start + 1 then.
    static func gaps(in file: FileDiff, newLineCount: Int) -> [Gap] {
        guard file.newPath != nil, file.oldPath != nil, newLineCount > 0 else { return [] }
        var gaps: [Gap] = []
        var previousLast = 0
        for (index, hunk) in file.hunks.enumerated() {
            let first = hunk.newCount == 0 ? hunk.newStart + 1 : hunk.newStart
            gaps.append(Gap(index: index, lines: first - 1 >= previousLast + 1 ? (previousLast + 1)...(first - 1) : nil))
            previousLast = hunk.newCount == 0 ? hunk.newStart : hunk.newStart + hunk.newCount - 1
        }
        if previousLast < newLineCount {
            gaps.append(Gap(index: file.hunks.count, lines: (previousLast + 1)...newLineCount))
        }
        return gaps
    }

    /// One collapsed row, or — expanded — every line in the gap as context.
    private static func gapRows(
        _ gap: Gap, file: FileDiff, new: HighlightedLines?, newLines: [String], expanded: Set<Int>
    ) -> [Row] {
        guard let lines = gap.lines else { return [] }
        guard expanded.contains(gap.index) else {
            let count = lines.count
            return [Row(
                kind: .gap, text: "⋯ \(count) unchanged \(count == 1 ? "line" : "lines")",
                oldLine: nil, newLine: nil, spans: [], gap: gap.index, gapLines: lines
            )]
        }
        return lines.compactMap { number in
            guard newLines.indices.contains(number - 1) else { return nil }
            return Row(
                kind: .context, text: newLines[number - 1],
                oldLine: oldLine(forUnchanged: number, in: file.hunks), newLine: number,
                spans: new?.spans(onLine: number) ?? []
            )
        }
    }

    /// The diff side by side. Within a hunk, a run of removed lines and the run
    /// of added lines after it pair up row for row; the shorter side is padded
    /// with filler, so a line and its replacement sit level.
    static func splitRows(
        _ file: FileDiff, old: HighlightedLines?, new: HighlightedLines?,
        newLines: [String], newLineCount: Int, expanded: Set<Int>
    ) -> (left: [Row], right: [Row]) {
        let filler = Row(kind: .filler, text: "", oldLine: nil, newLine: nil, spans: [])
        var left: [Row] = []
        var right: [Row] = []

        func appendGap(_ gap: Gap) {
            for row in gapRows(gap, file: file, new: new, newLines: newLines, expanded: expanded) {
                if row.kind == .gap {
                    left.append(row)
                    right.append(row)
                } else {
                    left.append(Row(kind: .context, text: row.text, oldLine: row.oldLine, newLine: nil, spans: row.spans))
                    right.append(Row(kind: .context, text: row.text, oldLine: nil, newLine: row.newLine, spans: row.spans))
                }
            }
        }

        let gaps = Self.gaps(in: file, newLineCount: newLineCount)
        for (index, hunk) in file.hunks.enumerated() {
            if gaps.indices.contains(index) { appendGap(gaps[index]) }
            let header = Row(kind: .hunkHeader, text: hunk.header, oldLine: nil, newLine: nil, spans: [])
            left.append(header)
            right.append(header)

            var removed: [Row] = []
            var added: [Row] = []
            func flush() {
                for offset in 0..<max(removed.count, added.count) {
                    left.append(offset < removed.count ? removed[offset] : filler)
                    right.append(offset < added.count ? added[offset] : filler)
                }
                removed.removeAll()
                added.removeAll()
            }
            for line in hunk.lines {
                switch line.kind {
                case .removed:
                    // A removed line after added ones starts a new block.
                    if !added.isEmpty { flush() }
                    removed.append(row(for: line, old: old, new: new))
                case .added:
                    added.append(row(for: line, old: old, new: new))
                case .context:
                    flush()
                    let oldSpans = line.oldLine.flatMap { old?.spans(onLine: $0) } ?? []
                    left.append(Row(kind: .context, text: line.text, oldLine: line.oldLine, newLine: nil, spans: oldSpans))
                    right.append(Row(kind: .context, text: line.text, oldLine: nil, newLine: line.newLine,
                                     spans: line.newLine.flatMap { new?.spans(onLine: $0) } ?? []))
                }
            }
            flush()
        }
        if gaps.count > file.hunks.count, let trailing = gaps.last { appendGap(trailing) }
        return (left, right)
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
