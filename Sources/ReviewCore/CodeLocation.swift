import Foundation

/// A place in a file on disk: where a definition lives, or a reference.
///
/// `line` is 1-based, matching the gutter and diff line numbers. `column` is
/// a UTF-16 offset into that line, which is how `NSString` and the language
/// servers both count.
public struct CodeLocation: Hashable, Sendable {
    public let file: URL
    public let line: Int
    public let column: Int
    /// Where the symbol ends, when the location names one; for highlighting.
    public let endLine: Int
    public let endColumn: Int

    public init(file: URL, line: Int, column: Int, endLine: Int? = nil, endColumn: Int? = nil) {
        self.file = file
        self.line = line
        self.column = column
        self.endLine = endLine ?? line
        self.endColumn = endColumn ?? column
    }

    /// The path below `root`, or nil when the file is outside it — the Go
    /// standard library, the module cache, a global TypeScript `lib.d.ts`.
    public func path(relativeTo root: URL) -> String? {
        let base = root.standardizedFileURL.path + "/"
        let path = file.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : nil
    }
}
