import Foundation

/// The languages the viewer highlights. Go and TypeScript are what gets
/// reviewed; plain JavaScript rides along on the TSX grammar, which parses
/// it.
public enum SyntaxLanguage: String, Hashable, Sendable, CaseIterable {
    case go
    case typeScript
    /// TSX, and JavaScript with or without JSX.
    case tsx

    /// Picks a language from a path's extension; nil means plain text.
    public init?(path: String) {
        switch (path as NSString).pathExtension.lowercased() {
        case "go": self = .go
        case "ts", "mts", "cts": self = .typeScript
        case "tsx", "js", "jsx", "mjs", "cjs": self = .tsx
        default: return nil
        }
    }
}
