import Foundation
import SwiftTreeSitter
import TreeSitterGo
import TreeSitterJSON
import TreeSitterSql
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

/// Parses a whole file with tree-sitter and returns its highlight spans.
public enum Highlighter {
    /// Spans in **paint order**: apply them first to last and let later spans
    /// overwrite earlier ones.
    ///
    /// - Longer spans paint first, so a node nested inside another wins — an
    ///   escape sequence inside a string, a type inside a comment directive.
    /// - On the same node, the query's own convention decides; see
    ///   `Precedence`.
    public static func highlight(_ text: String, as language: SyntaxLanguage) -> [HighlightSpan] {
        guard let compiled = try? CompiledLanguage.compiled(language) else { return [] }

        let parser = Parser()
        guard (try? parser.setLanguage(compiled.language)) != nil, let tree = parser.parse(text) else { return [] }

        // Resolving evaluates the queries' predicates (`#match?`, `#eq?`),
        // which need the source text.
        let matches = compiled.highlights.execute(in: tree).resolve(with: Predicate.Context(string: text))

        let captures = matches.flatMap(\.captures).sorted { lhs, rhs in
            if lhs.range.length != rhs.range.length { return lhs.range.length > rhs.range.length }
            if lhs.patternIndex != rhs.patternIndex {
                // Painted last wins, so the winning pattern sorts last.
                return switch compiled.precedence {
                case .firstPatternWins: lhs.patternIndex > rhs.patternIndex
                case .lastPatternWins: lhs.patternIndex < rhs.patternIndex
                }
            }
            return lhs.range.location < rhs.range.location
        }
        return captures.compactMap { capture in
            guard let name = capture.name, let kind = TokenKind(captureName: name) else { return nil }
            return HighlightSpan(range: capture.range, kind: kind)
        }
    }
}

/// Which of several patterns matching the same node shows.
///
/// The upstream queries disagree. Go's lists specific patterns first and
/// general ones after — a method call's `@function.method` before
/// `(field_identifier) @property` — and expects the first match to win.
/// JavaScript's opens with `(identifier) @variable` and refines it below, so
/// the last match must win. Each vendored query is tagged with the convention
/// it was written for; `HighlighterTests` pins both.
enum Precedence: Sendable {
    case firstPatternWins
    case lastPatternWins
}

/// A grammar and its compiled highlight query, built once per language.
struct CompiledLanguage: Sendable {
    let language: Language
    let highlights: Query
    let precedence: Precedence

    static func compiled(_ language: SyntaxLanguage) throws -> Self {
        switch language {
        case .go: try go.get()
        case .typeScript: try typeScript.get()
        case .tsx: try tsx.get()
        case .json: try json.get()
        case .yaml: try yaml.get()
        case .sql: try sql.get()
        }
    }

    // Compiling a query walks the whole grammar; do it once. Stored as Result
    // so a query that fails to compile fails every call the same way rather
    // than retrying.
    private static let go = Result {
        try Self(
            language: Language(language: tree_sitter_go()),
            source: VendoredQueries.goHighlights,
            precedence: .firstPatternWins
        )
    }

    private static let typeScript = Result {
        try Self(
            language: Language(language: tree_sitter_typescript()),
            source: VendoredQueries.javaScriptHighlights + "\n" + VendoredQueries.typeScriptHighlights,
            precedence: .lastPatternWins
        )
    }

    // JSX node types exist only in the TSX grammar; a query naming them fails
    // to compile against plain TypeScript, hence the separate concatenation.
    private static let tsx = Result {
        try Self(
            language: Language(language: tree_sitter_tsx()),
            source: VendoredQueries.javaScriptHighlights + "\n" + VendoredQueries.jsxHighlights + "\n"
                + VendoredQueries.typeScriptHighlights,
            precedence: .lastPatternWins
        )
    }

    // JSON's query names keys first and strings after: first match wins.
    private static let json = Result {
        try Self(
            language: Language(language: tree_sitter_json()),
            source: VendoredQueries.jsonHighlights,
            precedence: .firstPatternWins
        )
    }

    // YAML's lists every string, then the ones that are keys: last match wins.
    private static let yaml = Result {
        try Self(
            language: Language(language: tree_sitter_yaml()),
            source: VendoredQueries.yamlHighlights,
            precedence: .lastPatternWins
        )
    }

    // SQL's lists `(literal) @string`, then refines literals into numbers:
    // last match wins.
    private static let sql = Result {
        try Self(
            language: Language(language: tree_sitter_sql()),
            source: VendoredQueries.sqlHighlights,
            precedence: .lastPatternWins
        )
    }

    init(language: Language, source: String, precedence: Precedence) throws {
        self.language = language
        highlights = try Query(language: language, data: Data(source.utf8))
        self.precedence = precedence
    }
}
