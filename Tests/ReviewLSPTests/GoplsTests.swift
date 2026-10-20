import Foundation
import Testing
import ReviewLSP

/// Against the real gopls. These are the requests the viewer makes, on a
/// module small enough to load in a moment.
@Suite(.enabled(if: ServerFixture.isInstalled(.go)), .serialized)
struct GoplsTests {
    static let files = [
        "go.mod": "module example.com/fixture\n\ngo 1.21\n",
        "shapes/shape.go": """
            package shapes

            // Shape is anything with an area.
            type Shape interface {
            \tArea() float64
            }

            type Square struct{ Side float64 }

            func (s Square) Area() float64 { return s.Side * s.Side }

            // Total adds up every shape's area.
            func Total(shapes []Shape) float64 {
            \ttotal := 0.0
            \tfor _, s := range shapes {
            \t\ttotal += s.Area()
            \t}
            \treturn total
            }

            """,
        "main.go": """
            package main

            import "example.com/fixture/shapes"

            func main() {
            \tprintln(report())
            }

            func report() float64 {
            \treturn shapes.Total([]shapes.Shape{shapes.Square{Side: 2}})
            }

            """,
    ]

    @Test("Jumps from a call in one package to the function in another")
    func definition() async throws {
        let fixture = try await ServerFixture.start(.go, files: Self.files)
        let call = try fixture.position(of: "Total", in: "main.go")
        let found = try await fixture.server.definition(in: fixture.url("main.go"), at: call)
        await fixture.stop()

        let target = try #require(found.first)
        #expect(fixture.relativePath(target) == "shapes/shape.go")
        #expect(target.range.start.line == 12)
    }

    @Test("Finds the references to a function, without its declaration")
    func references() async throws {
        let fixture = try await ServerFixture.start(.go, files: Self.files)
        let declaration = try fixture.position(of: "Total", in: "shapes/shape.go", onLineWith: "func Total")
        let found = try await fixture.server.references(in: fixture.url("shapes/shape.go"), at: declaration)
        await fixture.stop()

        #expect(found.map(fixture.relativePath) == ["main.go"])
    }

    @Test("Walks callers two levels up")
    func incomingCalls() async throws {
        let fixture = try await ServerFixture.start(.go, files: Self.files)
        let declaration = try fixture.position(of: "Total", in: "shapes/shape.go", onLineWith: "func Total")
        let items = try await fixture.server.prepareCallHierarchy(in: fixture.url("shapes/shape.go"), at: declaration)
        let total = try #require(items.first)
        let callers = try await fixture.server.incomingCalls(to: total)
        let report = try #require(callers.first)
        let grandcallers = try await fixture.server.incomingCalls(to: report.caller)
        await fixture.stop()

        #expect(total.name == "Total")
        #expect(callers.map(\.caller.name) == ["report"])
        #expect(report.ranges.count == 1)
        #expect(grandcallers.map(\.caller.name) == ["main"])
    }

    @Test("Finds the types that implement an interface")
    func implementation() async throws {
        let fixture = try await ServerFixture.start(.go, files: Self.files)
        let interface = try fixture.position(of: "Shape", in: "shapes/shape.go", onLineWith: "type Shape")
        let found = try await fixture.server.implementation(in: fixture.url("shapes/shape.go"), at: interface)
        await fixture.stop()

        #expect(found.count == 1)
        #expect(found.first?.range.start.line == 7)
    }

    @Test("Describes a symbol on hover")
    func hover() async throws {
        let fixture = try await ServerFixture.start(.go, files: Self.files)
        let call = try fixture.position(of: "Total", in: "main.go")
        let hover = try await fixture.server.hover(in: fixture.url("main.go"), at: call)
        await fixture.stop()

        // Qualified, because the hover is in package main.
        #expect(hover?.markdown.contains("func shapes.Total(shapes []shapes.Shape) float64") == true)
        #expect(hover?.markdown.contains("adds up every shape") == true)
    }

    @Test("Counts characters in UTF-16, so a position after an emoji still lands")
    func utf16Positions() async throws {
        var files = Self.files
        files["main.go"] = """
            package main

            import "example.com/fixture/shapes"

            func main() {
            \tprintln("🙂🙂", shapes.Total(nil))
            }

            """
        let fixture = try await ServerFixture.start(.go, files: files)
        let call = try fixture.position(of: "Total", in: "main.go")
        let found = try await fixture.server.definition(in: fixture.url("main.go"), at: call)
        await fixture.stop()

        #expect(found.first.flatMap(fixture.relativePath) == "shapes/shape.go")
    }
}
