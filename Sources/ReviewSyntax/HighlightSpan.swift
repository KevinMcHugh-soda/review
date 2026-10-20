import Foundation

/// One coloured stretch of text. `range` is in UTF-16 code units — an
/// `NSRange` into the string as `NSString`/`NSTextView` index it.
public struct HighlightSpan: Hashable, Sendable {
    public let range: NSRange
    public let kind: TokenKind

    public init(range: NSRange, kind: TokenKind) {
        self.range = range
        self.kind = kind
    }
}
