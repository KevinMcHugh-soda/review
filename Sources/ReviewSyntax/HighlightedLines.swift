import Foundation

/// A file's highlight spans cut per line, so a diff can take the spans for
/// line 212 at head and line 198 at the merge base without re-parsing.
///
/// Lines are 1-based to match diff line numbers. Each line's spans are
/// relative to the start of that line, still in paint order, and clipped at
/// the line's end — a multi-line string or comment contributes a span to every
/// line it covers.
public struct HighlightedLines: Sendable {
    private let lines: [[HighlightSpan]]
    /// The file's functions, types and statements; see `SyntaxScope`.
    public let scopes: [SyntaxScope]

    public init(text: String, spans: [HighlightSpan], scopes: [SyntaxScope] = []) {
        self.scopes = scopes
        let starts = Self.lineStarts(text)
        let length = (text as NSString).length
        var lines = [[HighlightSpan]](repeating: [], count: starts.count)

        for span in spans {
            var location = span.range.location
            let end = min(span.range.location + span.range.length, length)
            var line = Self.line(containing: location, in: starts)
            while location < end, line < starts.count {
                let lineEnd = line + 1 < starts.count ? starts[line + 1] : length
                let pieceEnd = min(end, lineEnd)
                if pieceEnd > location {
                    let range = NSRange(location: location - starts[line], length: pieceEnd - location)
                    lines[line].append(HighlightSpan(range: range, kind: span.kind))
                }
                location = lineEnd
                line += 1
            }
        }
        self.lines = lines
    }

    public static func highlighting(_ text: String, as language: SyntaxLanguage?) -> Self {
        guard let language else { return Self(text: text, spans: []) }
        let analysis = Highlighter.analyze(text, as: language)
        return Self(text: text, spans: analysis.spans, scopes: analysis.scopes)
    }

    /// The spans on a 1-based line; empty past the end of the file.
    public func spans(onLine line: Int) -> [HighlightSpan] {
        lines.indices.contains(line - 1) ? lines[line - 1] : []
    }

    /// UTF-16 offsets at which each line begins. Splits on `\n` only, as git
    /// does; a `\r` stays part of its line.
    static func lineStarts(_ text: String) -> [Int] {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        return starts
    }

    private static func line(containing offset: Int, in starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }
}
