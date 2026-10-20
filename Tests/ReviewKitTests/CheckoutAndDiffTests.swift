import Foundation
import ReviewCore
import ReviewDiff
import ReviewGit
import Testing
@testable import ReviewKit

/// Clone, fetch, merge base, diff and parse against a real repository, with a
/// global git config that tries to break every step.
@Suite
struct CheckoutAndDiffTests {
    @Test("Diffs a pull request from its merge base, whatever the user's git config says")
    func diffsFromMergeBase() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await load(fixture)

        #expect(review.mergeBase == fixture.branchPointSHA)
        // unrelated.go landed on main after the branch point; a two-dot diff
        // against the base tip would wrongly show it as deleted.
        #expect(!review.files.contains { $0.path == "unrelated.go" })

        // Not uniqueKeysWithValues: a regression that loses paths should fail
        // this test, not crash the run.
        let byPath = Dictionary(review.files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(byPath["main.go"]?.status == .modified)
        #expect(byPath["main.go"]?.hunks.count == 3)
        #expect(byPath["renamed.go"]?.status == .renamed)
        #expect(byPath["renamed.go"]?.oldPath == "old.go")
        #expect(byPath["new.ts"]?.status == .added)
        #expect(byPath["gone.ts"]?.status == .deleted)
        #expect(byPath["logo.png"]?.isBinary == true)
        #expect(byPath["run.sh"]?.newMode == "100755")
        #expect(byPath["my file.go"]?.status == .modified)
        #expect(byPath["café.go"]?.status == .modified)
        // Full ids, despite the hostile config: viewed tracking compares them.
        #expect(byPath["main.go"]?.newBlob?.count == 40)
        #expect(byPath["noeol.txt"]?.hunks.first?.lines.allSatisfy { $0.kind == .context || $0.isMissingNewline } == true)
    }

    /// The property everything downstream relies on: a diff line's number
    /// names that exact line in that side's file. Comment anchoring, the
    /// gutter and LSP positions all assume it.
    @Test("Gives every diff line the number of that line in its side's file")
    func lineNumbersMatchFiles() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await load(fixture)

        for file in review.files where !file.isBinary {
            let old = try await review.text(of: file, on: .base).map(CodeDocument.lines)
            let new = try await review.text(of: file, on: .head).map(CodeDocument.lines)
            for line in file.hunks.flatMap(\.lines) {
                if let number = line.oldLine {
                    #expect(old?.line(number) == line.text, "\(file.path) base line \(number)")
                }
                if let number = line.newLine {
                    #expect(new?.line(number) == line.text, "\(file.path) head line \(number)")
                }
            }
        }
    }

    @Test("Maps every unchanged head line to its merge-base line in whole-file mode")
    func wholeFileOldLines() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await load(fixture)
        let file = try #require(review.files.first { $0.path == "main.go" })

        let document = try await review.document(for: file, mode: .file)
        let old = try #require(try await review.text(of: file, on: .base).map(CodeDocument.lines))
        #expect(document.rows.count == 40)
        #expect(document.rows.count { $0.kind == .added } == 2)
        for row in document.rows where row.kind == .context {
            let number = try #require(row.oldLine)
            #expect(old.line(number) == row.text, "head line \(row.newLine ?? 0)")
        }
    }

    @Test("Builds diff rows with a header per hunk and highlighting from the right side")
    func diffRows() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await load(fixture)
        let file = try #require(review.files.first { $0.path == "renamed.go" })

        let document = try await review.document(for: file, mode: .diff)
        #expect(document.rows.first?.kind == .hunkHeader)
        let removed = try #require(document.rows.first { $0.kind == .removed })
        let added = try #require(document.rows.first { $0.kind == .added })
        #expect(removed.text == "func Old() {}")
        #expect(added.text == "func New() {}")
        #expect(removed.spans.contains { $0.kind == .function })
        #expect(added.spans.contains { $0.kind == .function })
    }

    @Test("Reuses an existing clone and refetches into it")
    func reusesClone() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let checkouts = store(fixture)
        let first = try await checkouts.ensureRepository(for: fixture.reference)
        let marker = first.appendingPathComponent("review-marker")
        try Data().write(to: marker)
        let second = try await checkouts.ensureRepository(for: fixture.reference)
        #expect(first == second)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        try await checkouts.fetch(fixture.pullRequest, into: second)
    }

    @Test("Returns nil for a path that does not exist at a commit")
    func missingPath() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await load(fixture)
        let added = try #require(review.files.first { $0.path == "new.ts" })
        #expect(try await review.text(of: added, on: .base) == nil)
        #expect(try await review.text(of: added, on: .head) == "export const added = 2\nexport const more = 3\n")
    }

    // MARK: Helpers

    private func client(_ fixture: FixtureRepository) -> GitClient {
        GitClient(git: URL(fileURLWithPath: "/usr/bin/git"), gh: nil, environment: fixture.environment)
    }

    private func store(_ fixture: FixtureRepository) -> CheckoutStore {
        let source = fixture.source.absoluteString
        return CheckoutStore(
            root: fixture.directory.appendingPathComponent("support", isDirectory: true),
            git: client(fixture),
            remoteURL: { _ in source }
        )
    }

    /// What `ReviewLoader.load` does after the GitHub call, which needs a
    /// network.
    private func load(_ fixture: FixtureRepository) async throws -> LoadedReview {
        try await Self.load(fixture)
    }

    static func load(_ fixture: FixtureRepository) async throws -> LoadedReview {
        let git = GitClient(git: URL(fileURLWithPath: "/usr/bin/git"), gh: nil, environment: fixture.environment)
        let source = fixture.source.absoluteString
        let checkouts = CheckoutStore(
            root: fixture.directory.appendingPathComponent("support", isDirectory: true), git: git, remoteURL: { _ in source }
        )
        let repository = try await checkouts.ensureRepository(for: fixture.reference)
        try await checkouts.fetch(fixture.pullRequest, into: repository)
        let mergeBase = try await git.mergeBase(fixture.baseSHA, fixture.headSHA, in: repository)
        let patch = try await git.diff(from: mergeBase, to: fixture.headSHA, in: repository)
        return LoadedReview(
            pullRequest: fixture.pullRequest, mergeBase: mergeBase,
            files: try UnifiedDiffParser.parse(patch),
            merge: try await git.mergeTree(base: fixture.baseSHA, head: fixture.headSHA, in: repository),
            repository: repository, git: git
        )
    }
}

extension [String] {
    /// A 1-based line, or nil past either end.
    fileprivate func line(_ number: Int) -> String? {
        indices.contains(number - 1) ? self[number - 1] : nil
    }
}
