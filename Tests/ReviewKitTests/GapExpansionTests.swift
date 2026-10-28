import Foundation
import ReviewDiff
import ReviewSyntax
import Testing
@testable import ReviewKit

/// What a hidden run between hunks offers, from the scopes around it.
@Suite
struct GapExpansionTests {
    private func labels(
        _ run: ClosedRange<Int>, lineCount: Int = 100, scopes: [SyntaxScope]
    ) -> [String: ClosedRange<Int>] {
        Dictionary(uniqueKeysWithValues: CodeDocument.expansions(of: run, lineCount: lineCount, scopes: scopes)
            .map { ($0.label, $0.lines) })
    }

    @Test("Shows the start of the function a hunk below sits in")
    func restOfFunctionAbove() {
        let scopes = [SyntaxScope(lines: 40...70, label: "func run")]
        let offered = labels(10...49, scopes: scopes)
        #expect(offered["↑ rest of func run"] == 40...49)
    }

    @Test("Shows the end of the function a hunk above sits in")
    func restOfFunctionBelow() {
        let scopes = [SyntaxScope(lines: 5...30, label: "func load")]
        let offered = labels(21...60, scopes: scopes)
        #expect(offered["↓ rest of func load"] == 21...30)
    }

    @Test("Takes the smallest scope that reaches into the gap: the query, then its function")
    func smallestScopeFirst() {
        let scopes = [
            SyntaxScope(lines: 30...80, label: "func find"),
            SyntaxScope(lines: 45...55, label: "string"),
        ]
        #expect(labels(40...49, scopes: scopes)["↑ rest of string"] == 45...49)
        // Once the query is showing, the next one up is the function, which
        // holds the code above the gap too.
        #expect(labels(40...44, scopes: scopes)["↕ rest of func find"] == 40...44)
    }

    @Test("Offers one ↕ when one scope holds the code on both sides")
    func sameScopeBothSides() {
        let scopes = [SyntaxScope(lines: 1...100, label: "class Server")]
        let offered = labels(20...40, scopes: scopes)
        #expect(offered["↕ rest of class Server"] == 20...40)
        #expect(offered.keys.filter { $0.contains("rest of") }.count == 1)
    }

    @Test("Offers no steps for a run of five lines or fewer — a click shows it all")
    func shortRun() {
        #expect(labels(10...14, scopes: []).isEmpty)
        #expect(labels(10...15, scopes: []).keys.sorted() == ["↑ 5 lines", "↓ 5 lines"])
    }

    @Test("Builds a Go file's gap rows with the enclosing function named")
    func goDocument() throws {
        let old = (["package main", ""] + (1...12).map { "// filler \($0)" } + [
            "", "func handle(w int) string {", "\tx := 1", "\ty := 2", "\tz := 3", "\tq := 4", "\tr := 5",
            "\treturn \"old\"", "}",
        ]).joined(separator: "\n") + "\n"
        let new = old.replacingOccurrences(of: "return \"old\"", with: "return \"new\"")
        let patch = """
            diff --git a/main.go b/main.go
            --- a/main.go
            +++ b/main.go
            @@ -22,3 +22,3 @@ func handle(w int) string {
             \tr := 5
            -\treturn "old"
            +\treturn "new"
             }

            """
        let file = try #require(try UnifiedDiffParser.parse(patch).first)
        let document = CodeDocument(file: file, oldText: old, newText: new, mode: .diff)
        let gap = try #require(document.rows.first { $0.kind == .gap })
        #expect(gap.gapLines == 1...21)
        let rest = try #require(gap.expansions.first { $0.label == "↑ rest of func handle" })
        #expect(rest.lines == 16...21)
    }
}
