import Foundation
import ReviewCore
import ReviewGit
import Testing
@testable import ReviewKit

/// "Changes since last viewed": which head is remembered, and the diff from
/// it — exact after added commits and after a rebase, flagged when the old
/// head cannot be replayed onto the new merge base.
@Suite
struct ChangesSinceViewedTests {
    @Test("Remembers the head seen before the latest, and keeps it when the same head is reopened")
    func recordsViews() {
        var notes = ReviewNotes()
        notes.recordView(ofHead: "h1")
        #expect(notes.viewedHead == "h1")
        #expect(notes.previousViewedHead == nil)
        notes.recordView(ofHead: "h2")
        #expect(notes.previousViewedHead == "h1")
        notes.recordView(ofHead: "h2")
        #expect(notes.previousViewedHead == "h1")
        notes.recordView(ofHead: "h3")
        #expect(notes.previousViewedHead == "h2")
    }

    @Test("Loads notes saved before viewed heads existed")
    func oldNotesStillLoad() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notes = try decoder.decode(ReviewNotes.self, from: Data(#"{"drafts":[],"overview":[]}"#.utf8))
        #expect(notes.viewedHead == nil)
        #expect(notes.previousViewedHead == nil)
    }

    @Test("Shows only the files a new commit changed, against the old head")
    func addedCommit() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let shell = shell(fixture)
        try await shell.git("checkout", "--quiet", "feature")
        try shell.write("new.ts", "export const added = 2\nexport const more = 4\n")
        try await shell.git("commit", "--quiet", "-am", "follow-up")
        let newHead = try await shell.git("rev-parse", "HEAD")

        let since = try await changes(fixture, head: newHead, base: fixture.baseSHA, since: fixture.headSHA)
        #expect(since.changesSince == LoadedReview.ChangesSince(commit: fixture.headSHA, isExact: true))
        #expect(since.files.map(\.path) == ["new.ts"])
        let file = try #require(since.files.first)
        #expect(try await since.text(of: file, on: .base) == "export const added = 2\nexport const more = 3\n")
        // Drafts and posting still anchor on the PR's own diff.
        #expect(since.mergeBase == fixture.branchPointSHA)
    }

    @Test("Leaves out what the base branch changed when the author rebased")
    func rebase() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let shell = shell(fixture)
        // main already has unrelated.go; replay the feature onto it, with one
        // real change on top.
        try await shell.git("checkout", "--quiet", "-b", "rebased", "main")
        try await shell.git("cherry-pick", "--quiet", fixture.headSHA)
        try shell.write("new.ts", "export const added = 2\nexport const more = 4\n")
        try await shell.git("commit", "--quiet", "-am", "follow-up")
        let newHead = try await shell.git("rev-parse", "HEAD")

        let since = try await changes(fixture, head: newHead, base: fixture.baseSHA, since: fixture.headSHA)
        #expect(since.changesSince?.isExact == true)
        #expect(since.files.map(\.path) == ["new.ts"])
    }

    @Test("Says the comparison is not exact when the old head conflicts with the new base")
    func conflictedReplay() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let shell = shell(fixture)
        // main edits the line the feature edits; the author resolves it.
        var lines = FixtureRepository.mainGo.split(separator: "\n").map(String.init)
        lines[2] = "line 3 on main"
        try shell.write("main.go", lines.joined(separator: "\n") + "\n")
        try await shell.git("commit", "--quiet", "-am", "main edits line 3")
        let newBase = try await shell.git("rev-parse", "HEAD")
        try await shell.git("checkout", "--quiet", "-b", "rebased")
        try await shell.git("merge", "--quiet", "--no-commit", "--strategy=ours", fixture.headSHA)
        try await shell.git("read-tree", "-u", "--reset", fixture.headSHA)
        try shell.write("unrelated.go", "package widgets\n")
        let main = try String(contentsOf: fixture.source.appendingPathComponent("main.go"), encoding: .utf8)
        try shell.write("main.go", main.replacingOccurrences(of: "line 3 changed", with: "line 3 both"))
        try await shell.git("add", "-A")
        try await shell.git("commit", "--quiet", "-m", "merge main")
        let newHead = try await shell.git("rev-parse", "HEAD")

        let since = try await changes(fixture, head: newHead, base: newBase, since: fixture.headSHA)
        #expect(since.changesSince?.isExact == false)
        #expect(since.files.contains { $0.path == "main.go" })
    }

    private func shell(_ fixture: FixtureRepository) -> Shell {
        Shell(directory: fixture.source, environment: fixture.environment.merging([
            "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "f@example.com",
            "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "f@example.com",
        ]) { _, new in new })
    }

    /// Loads the fixture at its original head (the view), then at `head`,
    /// and narrows to the changes since `since`.
    private func changes(_ fixture: FixtureRepository, head: String, base: String, since: String) async throws -> LoadedReview {
        let git = GitClient(git: URL(fileURLWithPath: "/usr/bin/git"), gh: nil, environment: fixture.environment)
        let source = fixture.source.absoluteString
        let checkouts = CheckoutStore(
            root: fixture.directory.appendingPathComponent("support", isDirectory: true), git: git, remoteURL: { _ in source }
        )
        let repository = try await checkouts.ensureRepository(for: fixture.reference)
        try await checkouts.fetch(fixture.pullRequest, into: repository)

        let shell = shell(fixture)
        try await shell.git("update-ref", "refs/pull/7/head", head)
        let moved = PullRequest(
            reference: fixture.reference, title: "Fixture", body: "", author: "octocat", state: .open, isDraft: false,
            base: PullRequest.Branch(name: "main", sha: base),
            head: PullRequest.Branch(name: "feature", sha: head)
        )
        try await checkouts.fetch(moved, into: repository)
        let review = try await ReviewLoader.review(of: moved, in: repository, git: git)
        return try await review.changes(since: since)
    }
}
