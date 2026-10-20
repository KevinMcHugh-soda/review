/// Parses `git diff` output into files, hunks and numbered lines.
///
/// Expects the output of `GitClient.diff`, which pins the options that change
/// the format (prefixes, renames, colour, external diff tools) so the user's
/// git config cannot. Paths are taken from the `---`/`+++` and `rename`
/// lines where git prints them, and from the `diff --git` header only for
/// files that have none — binary and mode-only changes.
public struct UnifiedDiffParser {
    public enum ParseError: Error, Equatable, Sendable {
        case malformedHunkHeader(line: Int, text: String)
        /// A hunk promised more lines than the input holds.
        case truncatedHunk(line: Int)
    }

    private let lines: [String]
    private var index = 0

    private init(_ text: String) {
        // Split on the byte, not the Character: "\r\n" is one Character in
        // Swift, so a CRLF file's lines would never split on "\n".
        var lines = text.utf8
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        if lines.last == "" { lines.removeLast() }
        self.lines = lines
    }

    public static func parse(_ text: String) throws(ParseError) -> [FileDiff] {
        var parser = Self(text)
        return try parser.files()
    }

    private mutating func files() throws(ParseError) -> [FileDiff] {
        var files: [FileDiff] = []
        while index < lines.count {
            if lines[index].hasPrefix("diff --git ") {
                files.append(try file())
            } else {
                // Anything before the first header (there should be nothing).
                index += 1
            }
        }
        return files
    }

    private mutating func file() throws(ParseError) -> FileDiff {
        let header = String(lines[index].dropFirst("diff --git ".count))
        index += 1

        var oldPath: String?
        var newPath: String?
        var sawMinus = false
        var sawPlus = false
        var renameFrom: String?
        var renameTo: String?
        var isAdded = false
        var isDeleted = false
        var isBinary = false
        var oldMode: String?
        var newMode: String?
        var similarity: Int?
        var hunks: [Hunk] = []

        while index < lines.count, !lines[index].hasPrefix("diff --git ") {
            let line = lines[index]
            if line.hasPrefix("@@") {
                hunks.append(try hunk())
                continue
            }
            if let value = line.value(after: "--- ") {
                sawMinus = true
                oldPath = Self.path(value, prefix: "a/")
            } else if let value = line.value(after: "+++ ") {
                sawPlus = true
                newPath = Self.path(value, prefix: "b/")
            } else if let value = line.value(after: "rename from ") {
                renameFrom = Self.unquote(value)
            } else if let value = line.value(after: "rename to ") {
                renameTo = Self.unquote(value)
            } else if let value = line.value(after: "similarity index ") {
                similarity = Int(value.dropLast())
            } else if let value = line.value(after: "new file mode ") {
                isAdded = true
                newMode = value
            } else if let value = line.value(after: "deleted file mode ") {
                isDeleted = true
                oldMode = value
            } else if let value = line.value(after: "old mode ") {
                oldMode = value
            } else if let value = line.value(after: "new mode ") {
                newMode = value
            } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
                isBinary = true
            }
            index += 1
        }

        // Files with no ---/+++ lines (binary, mode-only, pure renames) name
        // themselves only in the header and the rename lines.
        let fromHeader = Self.headerPaths(header)
        if !sawMinus { oldPath = renameFrom ?? fromHeader?.old }
        if !sawPlus { newPath = renameTo ?? fromHeader?.new }
        if isAdded { oldPath = nil }
        if isDeleted { newPath = nil }

        return FileDiff(
            oldPath: oldPath, newPath: newPath, isBinary: isBinary,
            oldMode: oldMode, newMode: newMode, similarity: similarity, hunks: hunks
        )
    }

    private mutating func hunk() throws(ParseError) -> Hunk {
        let headerLine = index
        guard let header = HunkHeader(lines[index]) else {
            throw .malformedHunkHeader(line: index + 1, text: lines[index])
        }
        index += 1

        var oldLine = header.oldStart
        var newLine = header.newStart
        var oldRemaining = header.oldCount
        var newRemaining = header.newCount
        var body: [DiffLine] = []

        while oldRemaining > 0 || newRemaining > 0 {
            guard index < lines.count else { throw .truncatedHunk(line: headerLine + 1) }
            let line = lines[index]
            let text = String(line.dropFirst())
            switch line.first {
            case " ", nil:
                // An empty line is a context line whose leading space was
                // stripped by an editor or a mail client somewhere upstream.
                body.append(DiffLine(kind: .context, text: text, oldLine: oldLine, newLine: newLine))
                oldLine += 1
                newLine += 1
                oldRemaining -= 1
                newRemaining -= 1
            case "-":
                body.append(DiffLine(kind: .removed, text: text, oldLine: oldLine, newLine: nil))
                oldLine += 1
                oldRemaining -= 1
            case "+":
                body.append(DiffLine(kind: .added, text: text, oldLine: nil, newLine: newLine))
                newLine += 1
                newRemaining -= 1
            case "\\":
                if let last = body.popLast() { body.append(last.missingNewline()) }
            default:
                throw .truncatedHunk(line: headerLine + 1)
            }
            index += 1
        }
        // The marker can follow the hunk's final line.
        if index < lines.count, lines[index].hasPrefix("\\"), let last = body.popLast() {
            body.append(last.missingNewline())
            index += 1
        }

        return Hunk(
            oldStart: header.oldStart, oldCount: header.oldCount,
            newStart: header.newStart, newCount: header.newCount,
            section: header.section, lines: body
        )
    }

    // MARK: Paths

    /// `a/path`, `"a/quoted\tpath"` or `/dev/null`, with the trailing tab git
    /// appends when a name contains a space.
    static func path(_ value: String, prefix: String) -> String? {
        let trimmed = value.hasSuffix("\t") ? String(value.dropLast()) : value
        guard trimmed != "/dev/null" else { return nil }
        let unquoted = unquote(trimmed)
        return unquoted.hasPrefix(prefix) ? String(unquoted.dropFirst(prefix.count)) : unquoted
    }

    /// `a/X b/Y` when neither is quoted and X == Y, which is the only case a
    /// header with spaces in it can be split without guessing. Quoted halves
    /// are split exactly.
    static func headerPaths(_ header: String) -> (old: String, new: String)? {
        if header.hasPrefix("\""), let close = closingQuote(in: header) {
            let old = unquote(String(header[...close]))
            let rest = header[header.index(after: close)...].drop { $0 == " " }
            return (strip(old, "a/"), strip(unquote(String(rest)), "b/"))
        }
        let characters = Array(header)
        guard characters.count % 2 == 1 else { return nil }
        let half = characters.count / 2
        let old = String(characters[..<half])
        let new = String(characters[(half + 1)...])
        guard characters[half] == " ", old.hasPrefix("a/"), new.hasPrefix("b/"),
              old.dropFirst(2) == new.dropFirst(2)
        else { return nil }
        return (String(old.dropFirst(2)), String(new.dropFirst(2)))
    }

    private static func strip(_ path: String, _ prefix: String) -> String {
        path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    private static func closingQuote(in text: String) -> String.Index? {
        var escaped = false
        for index in text.indices.dropFirst() {
            if escaped {
                escaped = false
            } else if text[index] == "\\" {
                escaped = true
            } else if text[index] == "\"" {
                return index
            }
        }
        return nil
    }

    /// Undoes git's C-style quoting: `"a/caf\303\251"` → `a/café`. Octal
    /// escapes are UTF-8 bytes, so they are collected before decoding.
    static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        var bytes: [UInt8] = []
        var iterator = Array(value.utf8.dropFirst().dropLast()).makeIterator()
        while let byte = iterator.next() {
            guard byte == UInt8(ascii: "\\"), let escape = iterator.next() else {
                bytes.append(byte)
                continue
            }
            switch escape {
            case UInt8(ascii: "n"): bytes.append(0x0A)
            case UInt8(ascii: "t"): bytes.append(0x09)
            case UInt8(ascii: "r"): bytes.append(0x0D)
            case UInt8(ascii: "a"): bytes.append(0x07)
            case UInt8(ascii: "b"): bytes.append(0x08)
            case UInt8(ascii: "f"): bytes.append(0x0C)
            case UInt8(ascii: "v"): bytes.append(0x0B)
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                let second = iterator.next() ?? UInt8(ascii: "0")
                let third = iterator.next() ?? UInt8(ascii: "0")
                bytes.append((escape - 48) << 6 | (second - 48) << 3 | (third - 48))
            default: bytes.append(escape)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// `@@ -12,7 +12,8 @@ func handler(...)`. A count of 1 may be omitted.
private struct HunkHeader {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let section: String

    init?(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false)
        guard parts.count >= 4, parts[0] == "@@", parts[3] == "@@",
              let old = Self.range(parts[1], sign: "-"),
              let new = Self.range(parts[2], sign: "+")
        else { return nil }
        (oldStart, oldCount) = old
        (newStart, newCount) = new
        section = parts.count == 5 ? String(parts[4]) : ""
    }

    private static func range(_ part: Substring, sign: Character) -> (Int, Int)? {
        guard part.first == sign else { return nil }
        let numbers = part.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(numbers[0]) else { return nil }
        guard numbers.count == 2 else { return numbers.count == 1 ? (start, 1) : nil }
        guard let count = Int(numbers[1]) else { return nil }
        return (start, count)
    }
}

extension String {
    fileprivate func value(after prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
