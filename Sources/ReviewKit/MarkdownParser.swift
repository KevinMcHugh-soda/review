import Foundation

extension GitHubMarkdown {
    /// The blocks to lay out, with hidden comments gone and reference links
    /// resolved. Not a full CommonMark parser: it covers what PR descriptions,
    /// review comments, Claude's answers and hovers actually use.
    public static func blocks(_ markdown: String) -> [MarkdownBlock] {
        let lines = removingHiddenComments(markdown).components(separatedBy: "\n")
        return MarkdownParser(lines: lines).parse(lines)
    }
}

/// Line-based block parsing. Each container (list item, quote, details)
/// strips its own markers and parses what is left with the same rules.
struct MarkdownParser {
    /// `[label]: url` definitions, keyed by lowercased label.
    private let references: [String: String]

    init(lines: [String]) {
        var references: [String: String] = [:]
        var isInCode = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if Self.fence(trimmed) != nil {
                isInCode.toggle()
            } else if !isInCode, let (label, url) = Self.referenceDefinition(line) {
                references[label] = references[label] ?? url
            }
        }
        self.references = references
    }

    func parse(_ lines: [String]) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            let text = inline(paragraph.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = Self.fence(trimmed) {
                flushParagraph()
                let indent = Self.indent(of: line)
                var code: [String] = []
                index += 1
                while index < lines.count, !Self.closes(lines[index], fence: fence) {
                    code.append(Self.dropping(indent, from: lines[index]))
                    index += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
                index += 1
            } else if trimmed.isEmpty || Self.referenceDefinition(line) != nil {
                flushParagraph()
                index += 1
            } else if trimmed.lowercased().hasPrefix("<details") {
                flushParagraph()
                let end = Self.detailsEnd(lines, from: index)
                blocks.append(details(lines[index..<end].joined(separator: "\n")))
                index = end
            } else if let (level, text) = Self.heading(trimmed), Self.indent(of: line) < 4 {
                flushParagraph()
                blocks.append(.heading(level: level, text: inline(text)))
                index += 1
            } else if !paragraph.isEmpty, let level = Self.setextLevel(trimmed) {
                let text = inline(paragraph.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " "))
                paragraph = []
                blocks.append(.heading(level: level, text: text))
                index += 1
            } else if Self.isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix(">") else { break }
                    let content = next.dropFirst()
                    quoted.append(String(content.hasPrefix(" ") ? content.dropFirst() : content))
                    index += 1
                }
                blocks.append(.quote(parse(quoted)))
            } else if index + 1 < lines.count, line.contains("|"),
                let alignments = Self.delimiterRow(lines[index + 1]),
                Self.cells(line).count == alignments.count
            {
                flushParagraph()
                let header = Self.cells(line).map(inline)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let next = lines[index]
                    guard next.contains("|"), !next.trimmingCharacters(in: .whitespaces).isEmpty else { break }
                    let cells = Self.cells(next).map(inline)
                    rows.append((0..<header.count).map { $0 < cells.count ? cells[$0] : "" })
                    index += 1
                }
                blocks.append(.table(MarkdownTable(alignments: alignments, header: header, rows: rows)))
            } else if let marker = ListMarker(line), paragraph.isEmpty || marker.canInterruptParagraph {
                flushParagraph()
                let (items, end) = list(lines, from: index, first: marker)
                blocks.append(.list(items))
                index = end
            } else {
                paragraph.append(line)
                index += 1
            }
        }
        flushParagraph()
        return blocks
    }

    // MARK: Containers

    /// Consecutive items of one kind; each takes the lines indented under it,
    /// and unindented lines that continue its paragraph.
    private func list(_ lines: [String], from start: Int, first: ListMarker) -> ([MarkdownListItem], Int) {
        var items: [MarkdownListItem] = []
        var index = start
        while index < lines.count, let marker = ListMarker(lines[index]),
            marker.isOrdered == first.isOrdered, marker.indent < first.contentColumn
        {
            var body = [marker.content]
            var sawBlank = false
            index += 1
            while index < lines.count {
                let line = lines[index]
                let indent = Self.indent(of: line)
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    body.append("")
                    sawBlank = true
                } else if indent > marker.indent, indent >= marker.contentColumn || ListMarker(line) != nil {
                    // Nested lists indented less than the content column are
                    // common; GitHub is strict about it, this is lenient.
                    body.append(Self.dropping(min(indent, marker.contentColumn), from: line))
                    sawBlank = false
                } else if !sawBlank, !Self.startsBlock(line) {
                    body.append(line)
                } else {
                    break
                }
                index += 1
            }

            var item = marker.content
            var kind: MarkdownListItem.Marker = first.number.map { .number($0 + items.count) } ?? .bullet
            if let (isDone, rest) = Self.taskBox(item) {
                kind = .task(isDone: isDone)
                item = rest
            }
            body[0] = item
            items.append(MarkdownListItem(marker: kind, blocks: parse(body)))
        }
        return (items, index)
    }

    /// `<details>` HTML: the summary, and the rest parsed as Markdown, as
    /// GitHub does when a blank line follows the summary.
    private func details(_ html: String) -> MarkdownBlock {
        var text = html[...]
        if let open = text.range(of: ">") { text = text[open.upperBound...] }
        if let close = text.range(of: "</details>", options: [.caseInsensitive, .backwards]) {
            text = text[..<close.lowerBound]
        }
        var summary = "Details"
        if let open = text.range(of: "<summary", options: .caseInsensitive),
            let openEnd = text[open.upperBound...].range(of: ">"),
            let close = text[openEnd.upperBound...].range(of: "</summary>", options: .caseInsensitive)
        {
            let label = inline(String(text[openEnd.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
            if !label.isEmpty { summary = label }
            text = (text[..<open.lowerBound] + text[close.upperBound...])[...]
        }
        return .details(summary: summary, blocks: parse(String(text).components(separatedBy: "\n")))
    }

    /// The line after the `</details>` that closes the one opening at `start`.
    private static func detailsEnd(_ lines: [String], from start: Int) -> Int {
        var depth = 0
        for index in start..<lines.count {
            let line = lines[index].lowercased()
            depth += line.components(separatedBy: "<details").count - 1
            depth -= line.components(separatedBy: "</details").count - 1
            if depth <= 0 { return index + 1 }
        }
        return lines.count
    }

    // MARK: Inline

    /// Rewrites what `AttributedString` does not read — reference links and
    /// common inline HTML — leaving code spans alone.
    func inline(_ text: String) -> String {
        text.components(separatedBy: "`").enumerated().map { offset, part in
            offset.isMultiple(of: 2) ? resolvingReferences(Self.convertingHTML(part)) : part
        }
        .joined(separator: "`")
    }

    private static let referenceLink = try! NSRegularExpression(
        pattern: #"(?<![!\]\\])\[([^\[\]]+)\](?:\[([^\[\]]*)\])?(?![(:])"#
    )

    private func resolvingReferences(_ text: String) -> String {
        guard !references.isEmpty else { return text }
        var result = text
        let matches = Self.referenceLink.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: text), let label = Range(match.range(at: 1), in: text) else { continue }
            let explicit = Range(match.range(at: 2), in: text).map { text[$0] }.flatMap { $0.isEmpty ? nil : $0 }
            let key = (explicit ?? text[label]).lowercased()
            guard let url = references[key] else { continue }
            result.replaceSubrange(whole, with: "[\(text[label])](\(url))")
        }
        return result
    }

    private static let htmlRewrites: [(NSRegularExpression, String)] = [
        (#"<br\s*/?>"#, "\n"),
        (#"</?(b|strong)>"#, "**"),
        (#"</?(i|em)>"#, "*"),
        (#"</?(s|del|strike)>"#, "~~"),
        (#"</?code>"#, "`"),
        (#"<a\s[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#, "[$2]($1)"),
        (#"</?(p|div|span|sub|sup|small|center|kbd|ins|picture|source|img|a)(\s[^>]*)?/?>"#, ""),
    ]
    .map { (try! NSRegularExpression(pattern: $0, options: .caseInsensitive), $1) }

    private static func convertingHTML(_ text: String) -> String {
        guard text.contains("<") else { return text }
        return htmlRewrites.reduce(text) { text, rewrite in
            rewrite.0.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: rewrite.1
            )
        }
    }

    // MARK: Line tests

    private static func indent(of line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private static func dropping(_ count: Int, from line: String) -> String {
        String(line.dropFirst(min(count, indent(of: line))))
    }

    /// The opening run of a code fence: three or more backticks or tildes.
    private static func fence(_ trimmed: String) -> String? {
        for mark in ["`", "~"] {
            let run = trimmed.prefix { String($0) == mark }
            if run.count >= 3 { return String(run) }
        }
        return nil
    }

    private static func closes(_ line: String, fence: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(fence) && trimmed.allSatisfy { $0 == fence.first }
    }

    private static func heading(_ trimmed: String) -> (Int, String)? {
        let level = trimmed.prefix { $0 == "#" }.count
        let rest = trimmed.dropFirst(level)
        guard (1...6).contains(level), rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // A closing run of #s is decoration.
        let closing = text.reversed().prefix { $0 == "#" }.count
        if closing > 0, closing == text.count || text.dropLast(closing).last == " " {
            text = text.dropLast(closing).trimmingCharacters(in: .whitespaces)
        }
        return (level, text)
    }

    private static func setextLevel(_ trimmed: String) -> Int? {
        guard !trimmed.isEmpty else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let marks = trimmed.filter { $0 != " " }
        guard marks.count >= 3, let mark = marks.first, "-*_".contains(mark) else { return false }
        return marks.allSatisfy { $0 == mark }
    }

    /// Whether a line would begin a block of its own rather than continue a
    /// list item's paragraph.
    private static func startsBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return ListMarker(line) != nil || fence(trimmed) != nil || heading(trimmed) != nil
            || isRule(trimmed) || trimmed.hasPrefix(">") || trimmed.lowercased().hasPrefix("<details")
    }

    private static func referenceDefinition(_ line: String) -> (String, String)? {
        guard indent(of: line) < 4 else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), let close = trimmed.range(of: "]:") else { return nil }
        let label = trimmed[trimmed.index(after: trimmed.startIndex)..<close.lowerBound]
        let rest = trimmed[close.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !label.contains("["), var url = rest.split(separator: " ").first.map(String.init) else {
            return nil
        }
        if url.hasPrefix("<"), url.hasSuffix(">") { url = String(url.dropFirst().dropLast()) }
        return (label.lowercased(), url)
    }

    private static func taskBox(_ text: String) -> (Bool, String)? {
        for (box, isDone) in [("[ ]", false), ("[x]", true), ("[X]", true)] where text == box || text.hasPrefix(box + " ") {
            return (isDone, String(text.dropFirst(box.count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    // MARK: Tables

    /// `| --- | :-: | --: |`, as alignments; nil if the line isn't one.
    private static func delimiterRow(_ line: String) -> [MarkdownTable.Alignment]? {
        guard line.contains("|") || line.contains("-") else { return nil }
        let cells = cells(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [MarkdownTable.Alignment] = []
        for cell in cells {
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            let alignment: MarkdownTable.Alignment =
                switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
                case (true, true): .center
                case (false, true): .trailing
                default: .leading
                }
            alignments.append(alignment)
        }
        return alignments
    }

    /// A row's cells, split on unescaped pipes, outer pipes optional.
    private static func cells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)[...]
        if trimmed.hasPrefix("|") { trimmed = trimmed.dropFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") { trimmed = trimmed.dropLast() }
        var cells: [String] = []
        var cell = ""
        var isEscaped = false
        for character in trimmed {
            if character == "|", !isEscaped {
                cells.append(cell)
                cell = ""
            } else if character == "\\", !isEscaped {
                isEscaped = true
                continue
            } else {
                if isEscaped, character != "|" { cell.append("\\") }
                cell.append(character)
            }
            isEscaped = false
        }
        cells.append(cell)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// `- `, `* `, `+ `, `1. ` or `1) ` at the start of a line.
private struct ListMarker {
    let indent: Int
    let number: Int?
    /// Where the item's text starts; lines indented this far belong to it.
    let contentColumn: Int
    let content: String

    var isOrdered: Bool { number != nil }

    /// A bullet, or an ordered list starting at 1, may end a paragraph
    /// without a blank line between.
    var canInterruptParagraph: Bool { !content.isEmpty && (number == nil || number == 1) }

    init?(_ line: String) {
        let indent = line.prefix { $0 == " " }.count
        let rest = line.dropFirst(indent)
        let markerLength: Int
        if let first = rest.first, "-*+".contains(first) {
            markerLength = 1
            number = nil
        } else {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            guard (1...9).contains(digits.count), let delimiter = rest.dropFirst(digits.count).first, ".)".contains(delimiter) else {
                return nil
            }
            markerLength = digits.count + 1
            number = Int(digits)
        }
        let afterMarker = rest.dropFirst(markerLength)
        guard afterMarker.isEmpty || afterMarker.first == " " else { return nil }
        let spaces = afterMarker.prefix { $0 == " " }.count
        let text = afterMarker.dropFirst(spaces)
        let gap = (1...4).contains(spaces) && !text.isEmpty ? spaces : 1
        self.indent = indent
        contentColumn = indent + markerLength + gap
        content = String(text)
    }
}
