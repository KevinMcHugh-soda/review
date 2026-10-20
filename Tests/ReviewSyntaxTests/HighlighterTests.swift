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
