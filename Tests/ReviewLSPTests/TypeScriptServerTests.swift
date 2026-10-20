import Foundation
import Testing
import ReviewLSP

/// Against the real typescript-language-server, with no `node_modules` —
/// which is how a PR checkout looks, because this app never installs a PR's
/// dependencies.
@Suite(.enabled(if: ServerFixture.isInstalled(.typeScript)), .serialized)
struct TypeScriptServerTests {
    static let files = [
        "tsconfig.json": #"{ "compilerOptions": { "strict": true, "target": "es2020", "module": "esnext", "moduleResolution": "bundler" } }"#,
        "src/shapes.ts": """
            export interface Shape {
              area(): number
            }

            export class Square implements Shape {
              constructor(private side: number) {}
              area(): number {
                return this.side * this.side
              }
            }

            /** Adds up every shape's area. */
            export function total(shapes: Shape[]): number {
              return shapes.reduce((sum, s) => sum + s.area(), 0)
            }

            """,
        "src/main.ts": """
            import { Square, total } from "./shapes"

            export function report(): number {
              return total([new Square(2)])
            }

            report()

            """,
    ]

    @Test("Jumps from an imported call to its declaration")
    func definition() async throws {
        let fixture = try await ServerFixture.start(.typeScript, files: Self.files)
        let call = try fixture.position(of: "total", in: "src/main.ts", onLineWith: "return total")
        let found = try await fixture.server.definition(in: fixture.url("src/main.ts"), at: call)
        await fixture.stop()

        let target = try #require(found.first)
        #expect(fixture.relativePath(target) == "src/shapes.ts")
        #expect(target.range.start.line == 12)
    }

    @Test("Finds references across files")
    func references() async throws {
        let fixture = try await ServerFixture.start(.typeScript, files: Self.files)
        let declaration = try fixture.position(of: "total", in: "src/shapes.ts", onLineWith: "function total")
        let found = try await fixture.server.references(in: fixture.url("src/shapes.ts"), at: declaration)
        await fixture.stop()

        #expect(Set(found.compactMap(fixture.relativePath)) == ["src/main.ts"])
        // The call. Whether the import counts too depends on the server:
        // TypeScript 7 treats it as a declaration of a local alias and leaves
        // it out under `includeDeclaration: false`; tsserver includes it.
        #expect(found.contains { $0.range.start.line == 3 })
    }

    @Test("Finds callers through the call hierarchy")
    func incomingCalls() async throws {
        let fixture = try await ServerFixture.start(.typeScript, files: Self.files)
        let declaration = try fixture.position(of: "total", in: "src/shapes.ts", onLineWith: "function total")
        let items = try await fixture.server.prepareCallHierarchy(in: fixture.url("src/shapes.ts"), at: declaration)
        let callers = try await fixture.server.incomingCalls(to: try #require(items.first))
        await fixture.stop()

        #expect(callers.map(\.caller.name) == ["report"])
    }
}
