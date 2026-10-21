import Foundation
import ReviewDiff
import ReviewGit
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

    /// harmony#13296 branched before main marked `internal/*api/client.go`
    /// generated; its head's `.gitattributes` has no such rule.
    @Test("Takes a generated rule the base added after the branch point")
    func generatedOnBase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-attr-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let shell = Shell(directory: directory, environment: [
            "PATH": "/usr/bin:/bin", "HOME": directory.path, "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "f@example.com",
            "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "f@example.com",
        ])
        try await shell.git("init", "--quiet", "--initial-branch=main")
        try shell.write("client.go", "package api\n")
        try await shell.git("add", "-A")
        try await shell.git("commit", "--quiet", "-m", "branch point")
        let head = try await shell.git("rev-parse", "HEAD")
        try shell.write(".gitattributes", "client.go linguist-generated=true\n")
        try await shell.git("add", "-A")
        try await shell.git("commit", "--quiet", "-m", "mark generated")
        let base = try await shell.git("rev-parse", "HEAD")

        let git = GitClient(git: URL(fileURLWithPath: "/usr/bin/git"), gh: nil, environment: shell.environment)
        #expect(try await git.generatedPaths(["client.go"], at: head, in: directory).isEmpty)
        #expect(try await git.generatedPaths(["client.go"], atAnyOf: [head, base], in: directory) == ["client.go"])
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
