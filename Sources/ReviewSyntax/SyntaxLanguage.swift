import Foundation

/// The languages the viewer highlights. Go and TypeScript are what gets
/// reviewed; plain JavaScript rides along on the TSX grammar, which parses
/// it. JSON and YAML are the configuration that comes with them, SQL the
/// migrations and queries.
public enum SyntaxLanguage: String, Hashable, Sendable, CaseIterable {
    case go
    case typeScript
    /// TSX, and JavaScript with or without JSX.
    case tsx
    /// JSON, and JSON with comments (`tsconfig.json` has them; the grammar
    /// parses `//` and `/* */`).
    case json
    case yaml
    case sql

    /// Picks a language from a path's extension; nil means plain text.
    public init?(path: String) {
        switch (path as NSString).pathExtension.lowercased() {
        case "go": self = .go
        case "ts", "mts", "cts": self = .typeScript
        case "tsx", "js", "jsx", "mjs", "cjs": self = .tsx
        case "json", "jsonc", "json5": self = .json
        case "yaml", "yml": self = .yaml
        case "sql", "psql", "pgsql": self = .sql
        default: return nil
        }
    }
}
