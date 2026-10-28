import Foundation
import Testing
@testable import ReviewSyntax

@Suite
struct HighlighterTests {
    /// A query naming a node type the grammar lacks fails to compile, and the
    /// highlighter then silently returns nothing. This is the guard.
    @Test("Compiles the highlight query for every language", arguments: SyntaxLanguage.allCases)
    func compiles(language: SyntaxLanguage) throws {
        _ = try CompiledLanguage.compiled(language)
    }

    @Test("Colours a Go function name as a function and its keyword as a keyword")
    func goFunction() {
        let text = "package main\n\nfunc handle(w int) string { return \"ok\" }\n"
        let kinds = finalKinds(text, .go)
        #expect(kinds["func"] == .keyword)
        #expect(kinds["handle"] == .function)
        #expect(kinds["string"] == .type)
        #expect(kinds["\"ok\""] == .string)
    }

    /// Go's query lists specific patterns first (`call_expression` with a
    /// selector → `@function.method`) and general ones later
    /// (`(field_identifier) @property`); the first must win there.
    @Test("Colours a Go method call as a function and a field access as a property")
    func goMethodCall() {
        let text = "package main\n\nfunc f() { cmd.CommandPath(); _ = cfg.Name }\n"
        let kinds = finalKinds(text, .go)
        #expect(kinds["CommandPath"] == .function)
        #expect(kinds["Name"] == .property)
    }

    @Test("Colours TypeScript types, keywords and strings")
    func typeScript() {
        let text = "export interface User { name: string }\nconst greet = (u: User): string => `hi ${u.name}`\n"
        let kinds = finalKinds(text, .typeScript)
        #expect(kinds["interface"] == .keyword)
        #expect(kinds["User"] == .type)
        #expect(kinds["const"] == .keyword)
        #expect(kinds["greet"] == .function)
    }

    @Test("Colours JSON keys apart from string values, with numbers, literals and comments")
    func json() {
        let text = "{\n  // tsconfig allows comments\n  \"name\": \"review\",\n  \"strict\": true,\n  \"port\": 8080,\n  \"tags\": null\n}\n"
        let kinds = finalKinds(text, .json)
        #expect(kinds["\"name\""] == .property)
        #expect(kinds["\"review\""] == .string)
        #expect(kinds["true"] == .keyword || kinds["true"] == .constant)
        #expect(kinds["8080"] == .number)
        #expect(kinds["null"] == .keyword || kinds["null"] == .constant)
        #expect(kinds["// tsconfig allows comments"] == .comment)
    }

    @Test("Colours YAML keys apart from values, with numbers, booleans, anchors and comments")
    func yaml() {
        let text = "# deploy config\nname: review\nreplicas: 3\nenabled: true\nbase: &defaults\n  image: \"app:1.0\"\nprod:\n  <<: *defaults\n"
        let kinds = finalKinds(text, .yaml)
        #expect(kinds["name"] == .property)
        #expect(kinds["review"] == .string)
        #expect(kinds["3"] == .number)
        #expect(kinds["true"] == .constant)
        #expect(kinds["# deploy config"] == .comment)
        #expect(kinds["\"app:1.0\""] == .string)
        #expect(kinds["defaults"] == .constant)
    }

    @Test("Colours SQL keywords, strings, numbers, comments, functions and tables")
    func sql() {
        let text = """
            -- add the ledger table
            CREATE TABLE ledger_entries (
              id BIGINT PRIMARY KEY,
              memo TEXT NOT NULL DEFAULT 'none'
            );
            SELECT count(*) FROM ledger_entries WHERE amount > 100 AND rate = 0.5;

            """
        let kinds = finalKinds(text, .sql)
        #expect(kinds["-- add the ledger table"] == .comment)
        #expect(kinds["CREATE"] == .keyword)
        #expect(kinds["SELECT"] == .keyword)
        #expect(kinds["'none'"] == .string)
        // Numbers rely on the `%d` → `[0-9]` rewrite of the vendored query.
        #expect(kinds["100"] == .number)
        #expect(kinds["0.5"] == .number)
        #expect(kinds["count"] == .function)
        #expect(kinds["BIGINT"] == .type)
        #expect(kinds["ledger_entries"] == .type)
    }

    @Test("Parses JSX with the TSX grammar")
    func tsx() {
        let text = "export const A = () => <div className=\"x\">hi</div>\n"
        let kinds = finalKinds(text, .tsx)
        #expect(kinds["div"] == .tag)
        #expect(kinds["className"] == .property)
    }

    @Test("Lets an escape sequence show through the string around it")
    func nestedEscape() {
        let text = "package main\n\nvar s = \"a\\nb\"\n"
        #expect(finalKinds(text, .go)["\\n"] == .escape)
    }

    @Test("Splits a multi-line comment across every line it covers")
    func multilineComment() {
        let text = "package main\n/* one\ntwo\nthree */\nvar x = 1\n"
        let lines = HighlightedLines.highlighting(text, as: .go)
        for line in 2...4 {
            #expect(lines.spans(onLine: line).contains { $0.kind == .comment && $0.range.location == 0 })
        }
        #expect(lines.spans(onLine: 5).allSatisfy { $0.kind != .comment })
        #expect(lines.spans(onLine: 99).isEmpty)
    }

    @Test("Measures spans in UTF-16, as NSString does")
    func utf16() {
        let text = "package main\n\nvar e = \"🙂\"; func f() {}\n"
        let kinds = finalKinds(text, .go)
        #expect(kinds["\"🙂\""] == .string)
        #expect(kinds["f"] == .function)
    }

    @Test("Picks a language from the file extension")
    func languages() {
        #expect(SyntaxLanguage(path: "pkg/ledger/api.go") == .go)
        #expect(SyntaxLanguage(path: "src/app.ts") == .typeScript)
        #expect(SyntaxLanguage(path: "src/App.tsx") == .tsx)
        #expect(SyntaxLanguage(path: "index.mjs") == .tsx)
        #expect(SyntaxLanguage(path: "tsconfig.json") == .json)
        #expect(SyntaxLanguage(path: ".github/workflows/ci.yml") == .yaml)
        #expect(SyntaxLanguage(path: "deploy/values.yaml") == .yaml)
        #expect(SyntaxLanguage(path: "migrations/0042_ledger.sql") == .sql)
        #expect(SyntaxLanguage(path: "README.md") == nil)
    }

    /// The kind each distinct token text ends up painted with, after every
    /// span is applied in order.
    private func finalKinds(_ text: String, _ language: SyntaxLanguage) -> [String: TokenKind] {
        let string = text as NSString
        var painted = [TokenKind?](repeating: nil, count: string.length)
        for span in Highlighter.highlight(text, as: language) {
            for offset in span.range.location..<(span.range.location + span.range.length) {
                painted[offset] = span.kind
            }
        }
        var result: [String: TokenKind] = [:]
        for span in Highlighter.highlight(text, as: language) {
            let token = string.substring(with: span.range)
            let offsets = span.range.location..<(span.range.location + span.range.length)
            if let kind = painted[span.range.location], offsets.allSatisfy({ painted[$0] == kind }) {
                result[token] = kind
            }
        }
        return result
    }
}

@Suite
struct SyntaxScopeTests {
    private func scopes(_ text: String, _ language: SyntaxLanguage) -> [String: ClosedRange<Int>] {
        Dictionary(Highlighter.analyze(text, as: language).scopes.map { ($0.label, $0.lines) }) { first, _ in first }
    }

    @Test("Finds Go functions, methods, types and multi-line raw strings")
    func go() {
        let text = """
            package main

            type Server struct {
            \tname string
            }

            func (s *Server) Run() {
            \tq := `
            \t\tSELECT *
            \t\tFROM users`
            \t_ = q
            }

            func main() {
            \tprintln("one line")
            }
            """
        let found = scopes(text, .go)
        #expect(found["type Server"] == 3...5)
        #expect(found["func Run"] == 7...12)
        #expect(found["string"] == 8...10)
        #expect(found["func main"] == 14...16)
    }

    @Test("Finds TypeScript classes, methods and arrow functions bound to a name")
    func typeScript() {
        let text = """
            export class Store {
              load(id: string) {
                return id
              }
            }

            const greet = (name: string) => {
              return name
            }
            """
        let found = scopes(text, .typeScript)
        #expect(found["class Store"] == 1...5)
        #expect(found["method load"] == 2...4)
        #expect(found["function greet"] == 7...9)
    }

    @Test("Finds each SQL statement")
    func sql() {
        let text = "SELECT id\nFROM users\nWHERE id = 1;\n\nUPDATE users\nSET name = 'x';\n"
        let found = Highlighter.analyze(text, as: .sql).scopes.filter { $0.label == "statement" }.map(\.lines)
        #expect(found == [1...3, 5...6])
    }
}
