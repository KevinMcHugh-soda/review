import Foundation
import ReviewCore
import ReviewDiff
import ReviewGit
import ReviewProcess
import Testing
@testable import ReviewKit

/// Worktree, merge preview and navigation on a Go repository, through real
/// git and the real gopls.
@Suite(.serialized)
struct NavigationTests {
    @Test("Checks out head, and moves the checkout when the PR gains a commit")
    func worktreeFollowsHead() async throws {
        let fixture = try await GoFixture.make()
        defer { fixture.remove() }
        let review = try await fixture.load()

        let worktree = try await review.checkOut(using: fixture.checkouts)
        #expect(try String(contentsOf: worktree.appendingPathComponent("main.go"), encoding: .utf8).contains("Describe"))

        let newHead = try await fixture.pushToPullRequest("main.go", GoFixture.mainGo + "// one more\n")
        let updated = try await fixture.load(head: newHead)
        let moved = try await updated.checkOut(using: fixture.checkouts)
        #expect(moved == worktree)
        #expect(try String(contentsOf: moved.appendingPathComponent("main.go"), encoding: .utf8).hasSuffix("// one more\n"))
    }

    @Test("Jumps from a line the PR added to a definition in a file it did not touch",
          .enabled(if: GoFixture.hasGopls))
    func definitionFromDiffRow() async throws {
        let fixture = try await GoFixture.make()
        defer { fixture.remove() }
        let review = try await fixture.load()
        let worktree = try await review.checkOut(using: fixture.checkouts)
        let navigator = Navigator(root: worktree, environment: await GoFixture.environment.value)
        defer { Task { await navigator.shutdown() } }

        // The row the viewer would show, and the column of the click.
        let file = try #require(review.files.first { $0.path == "main.go" })
        let document = try await review.document(for: file, mode: .diff)
        let row = try #require(document.rows.first { $0.kind == .added && $0.text.contains("Describe") })
        let column = (row.text as NSString).range(of: "Describe").location

        let found = try await navigator.definition(path: "main.go", line: try #require(row.newLine), column: column)
        let target = try #require(found.first)
        #expect(target.path(relativeTo: worktree) == "shapes/describe.go")
        #expect(target.line == 3)

        let callers = try #require(try await navigator.callHierarchy(path: "shapes/describe.go", line: 3, column: 5))
        #expect(try await navigator.callers(of: callers).map(\.name) == ["main"])
    }

    @Test("Shows the whole file as it will be after merging into a base that moved")
    func afterMerge() async throws {
        let fixture = try await GoFixture.make(baseAlsoEditsMain: true)
        defer { fixture.remove() }
        let review = try await fixture.load()
        let file = try #require(review.files.first { $0.path == "main.go" })

        let merged = try await review.document(for: file, mode: .file)
        #expect(merged.source == .afterMerge)
        #expect(!merged.isNavigable)
        let text = merged.rows.map(\.text)
        // The base's change and the PR's change, together.
        #expect(text.contains("// edited on main"))
        #expect(text.contains { $0.contains("Describe") })
        // Only what the merge adds is marked: the PR's lines, not main's.
        #expect(merged.rows.filter { $0.kind == .added }.map(\.text).allSatisfy { !$0.contains("edited on main") })
        #expect(merged.rows.contains { $0.kind == .added && $0.text.contains("Describe") })

        let diff = try await review.document(for: file, mode: .diff)
        #expect(diff.source == .pullRequest)
    }

    /// GitHub leaves `base.sha` where it was until the PR itself changes; for
    /// an old PR it can still be the branch point.
    @Test("Merges into the fetched base tip when the API's base commit is stale")
    func afterMergeWithStaleBase() async throws {
        let fixture = try await GoFixture.make(baseAlsoEditsMain: true)
        defer { fixture.remove() }
        let branchPoint = try await fixture.source.git("merge-base", fixture.base, fixture.head)
        let review = try await fixture.load(apiBase: branchPoint)
        #expect(review.mergeBase == branchPoint)
        #expect(review.baseTip == fixture.base)

        let file = try #require(review.files.first { $0.path == "main.go" })
        let merged = try await review.document(for: file, mode: .file)
        #expect(merged.source == .afterMerge)
        #expect(merged.rows.contains { $0.text == "// edited on main" })
        #expect(merged.rows.filter { $0.kind == .added }.allSatisfy { !$0.text.contains("edited on main") })
    }
}

/// A Go module: `main.go` calls into `shapes`, and the PR adds a call to a
/// function in a file the PR does not touch.
private struct GoFixture {
    let directory: URL
    let source: Shell
    let checkouts: CheckoutStore
    let git: GitClient
    let reference = PullRequestReference(owner: "acme", repository: "geometry", number: 3)
    let base: String
    let head: String

    static let environment = Task { await ToolEnvironment.loginShell() }
    static let hasGopls = FileManager.default.isExecutableFile(atPath: NSHomeDirectory() + "/go/bin/gopls")
        || FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/gopls")

    static let mainGo = """
        package main

        import "example.com/geometry/shapes"

        func main() {
        \tprintln(shapes.Area(2))
        \tprintln(shapes.Describe(2))
        }

        """

    static func make(baseAlsoEditsMain: Bool = false) async throws -> Self {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-nav-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        let sourceURL = directory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        let environment = [
            "PATH": "/usr/bin:/bin", "HOME": directory.path, "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "f@example.com",
            "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "f@example.com",
        ]
        let source = Shell(directory: sourceURL, environment: environment)

        try await source.git("init", "--quiet", "--initial-branch=main")
        try source.write("go.mod", "module example.com/geometry\n\ngo 1.21\n")
        try FileManager.default.createDirectory(at: sourceURL.appendingPathComponent("shapes"), withIntermediateDirectories: true)
        try source.write("shapes/area.go", "package shapes\n\nfunc Area(side float64) float64 { return side * side }\n")
        try source.write("shapes/describe.go", "package shapes\n\nfunc Describe(side float64) string { return \"square\" }\n")
        try source.write("main.go", mainGo.replacingOccurrences(of: "\tprintln(shapes.Describe(2))\n", with: ""))
        try await source.git("add", "-A")
        try await source.git("commit", "--quiet", "-m", "base")

        try await source.git("checkout", "--quiet", "-b", "feature")
        try source.write("main.go", mainGo)
        try await source.git("commit", "--quiet", "-am", "describe")
        let head = try await source.git("rev-parse", "HEAD")
        try await source.git("update-ref", "refs/pull/3/head", head)
        try await source.git("checkout", "--quiet", "main")

        if baseAlsoEditsMain {
            try source.write("main.go", "// edited on main\n" + mainGo.replacingOccurrences(of: "\tprintln(shapes.Describe(2))\n", with: ""))
            try await source.git("commit", "--quiet", "-am", "meanwhile")
        }
        let base = try await source.git("rev-parse", "HEAD")

        let git = GitClient(git: URL(fileURLWithPath: "/usr/bin/git"), gh: nil, environment: environment)
        let remote = sourceURL.absoluteString
        let checkouts = CheckoutStore(
            root: directory.appendingPathComponent("support", isDirectory: true), git: git, remoteURL: { _ in remote }
        )
        return Self(directory: directory, source: source, checkouts: checkouts, git: git, base: base, head: head)
    }

    func pushToPullRequest(_ path: String, _ text: String) async throws -> String {
        try await source.git("checkout", "--quiet", "feature")
        try source.write(path, text)
        try await source.git("commit", "--quiet", "-am", "more")
        let sha = try await source.git("rev-parse", "HEAD")
        try await source.git("update-ref", "refs/pull/3/head", sha)
        try await source.git("checkout", "--quiet", "main")
        return sha
    }

    /// `apiBase` stands in for a stale `base.sha` from GitHub's API.
    func load(head: String? = nil, apiBase: String? = nil) async throws -> LoadedReview {
        let pullRequest = PullRequest(
            reference: reference, title: "Describe", body: "", author: "octocat", state: .open, isDraft: false,
            base: PullRequest.Branch(name: "main", sha: apiBase ?? base),
            head: PullRequest.Branch(name: "feature", sha: head ?? self.head)
        )
        let repository = try await checkouts.ensureRepository(for: reference)
        try await checkouts.fetch(pullRequest, into: repository)
        return try await ReviewLoader.review(of: pullRequest, in: repository, git: git)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
