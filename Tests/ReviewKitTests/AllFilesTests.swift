import Foundation
import ReviewDiff
import Testing
@testable import ReviewKit

/// The all-files view and generated files, on the fixture repository — which
/// marks `*.pb.go` generated in `.gitattributes` and `not-generated.go`
/// explicitly not.
@Suite
struct AllFilesTests {
    @Test("Finds generated files from .gitattributes and puts them last")
    func generatedLast() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await CheckoutAndDiffTests.load(fixture)

        #expect(review.generatedPaths == ["api.pb.go"])
        #expect(review.files.last?.path == "api.pb.go")
        #expect(review.files.contains { $0.path == "not-generated.go" })
    }

    @Test("Shows every file under its own header, in order, each row knowing its file")
    func combined() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await CheckoutAndDiffTests.load(fixture)
        let document = try await review.allFilesDocument(mode: .diff)

        let headers = document.rows.filter { $0.kind == .fileHeader }
        #expect(headers.map(\.file) == review.files.indices.map(Optional.some))
        #expect(headers.first?.text.hasPrefix(review.files[0].path) == true)
        // Every row after a header belongs to that header's file.
        var current: Int?
        for row in document.rows {
            if row.kind == .fileHeader { current = row.file }
            #expect(row.file == current)
        }
        // The same line number in two files resolves by file.
        let main = try #require(review.files.firstIndex { $0.path == "main.go" })
        let row = try #require(document.row(forNewLine: 3, file: main))
        #expect(document.rows[row].text == "line 3 changed")
    }

    @Test("Collapses the files it is told to, leaving their header and why")
    func collapsed() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await CheckoutAndDiffTests.load(fixture)
        let document = try await review.allFilesDocument(mode: .diff, collapsed: review.generatedPaths)

        let generated = try #require(review.files.firstIndex { $0.path == "api.pb.go" })
        let header = try #require(document.headerRow(forFile: generated))
        #expect(document.rows[header].text.contains("generated"))
        #expect(document.rows[header].text.contains("click to show"))
        #expect(!document.rows.contains { $0.file == generated && $0.kind != .fileHeader })

        let open = try await review.allFilesDocument(mode: .diff)
        #expect(open.rows.contains { $0.file == generated && $0.kind == .added })
    }

    @Test("Finds the gap that hides a line, so a jump can open it")
    func gapForJump() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await CheckoutAndDiffTests.load(fixture)
        let document = try await review.allFilesDocument(mode: .diff)
        let main = try #require(review.files.firstIndex { $0.path == "main.go" })

        // Line 12 of main.go is between the first two hunks.
        #expect(document.row(forNewLine: 12, file: main) == nil)
        let gap = try #require(document.gapRow(containing: 12, file: main))
        #expect(document.rows[gap].gapLines?.contains(12) == true)
    }

    @Test("Builds a side-by-side all-files document with headers on both sides")
    func split() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await CheckoutAndDiffTests.load(fixture)
        let document = try await review.allFilesDocument(mode: .split)
        let left = try #require(document.leftRows)
        #expect(left.count == document.rows.count)
        for (base, head) in zip(left, document.rows) where head.kind == .fileHeader {
            #expect(base.kind == .fileHeader)
            #expect(base.file == head.file)
        }
    }
}
