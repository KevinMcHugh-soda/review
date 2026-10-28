import Foundation

/// A stretch of a file worth reading whole: a function, a type, a SQL
/// statement, a multi-line string (in Go and TypeScript, usually a query).
///
/// The gaps between hunks offer "the rest of" the scope a hunk sits in, so a
/// change in the middle of a function can be read with its signature.
public struct SyntaxScope: Hashable, Sendable {
    /// 1-based lines, first to last.
    public let lines: ClosedRange<Int>
    /// What to call it: "func run", "class Server", "statement".
    public let label: String

    public init(lines: ClosedRange<Int>, label: String) {
        self.lines = lines
        self.label = label
    }
}

/// Which nodes count as scopes, per language. Our own, not vendored: each
/// match has one `@scope.<noun>` capture (or bare `@scope`) and, optionally,
/// a `@name`; the label is the noun and the name's text.
enum ScopeQueries {
    static let go = """
        (function_declaration name: (identifier) @name) @scope.func
        (method_declaration name: (field_identifier) @name) @scope.func
        (type_declaration (type_spec name: (type_identifier) @name)) @scope.type
        (func_literal) @scope.closure
        (raw_string_literal) @scope.string
        """

    /// Shared by TypeScript and TSX; it names no JSX nodes.
    static let typeScript = """
        (function_declaration name: (identifier) @name) @scope.function
        (generator_function_declaration name: (identifier) @name) @scope.function
        (lexical_declaration
          (variable_declarator
            name: (identifier) @name
            value: [(arrow_function) (function_expression)])) @scope.function
        (method_definition name: (_) @name) @scope.method
        (class_declaration name: (_) @name) @scope.class
        (abstract_class_declaration name: (_) @name) @scope.class
        (interface_declaration name: (_) @name) @scope.interface
        (type_alias_declaration name: (_) @name) @scope.type
        (enum_declaration name: (_) @name) @scope.enum
        (template_string) @scope.string
        """

    static let json = """
        (pair key: (string) @name value: [(object) (array)]) @scope
        """

    static let yaml = """
        (block_mapping_pair key: (_) @name value: (block_node)) @scope
        """

    static let sql = """
        (statement) @scope.statement
        """
}
