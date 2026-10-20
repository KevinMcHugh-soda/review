import Foundation
import ReviewCore
import ReviewDiff
import Testing
@testable import ReviewKit

/// Where drafts land, by rule. GitHub rejects the whole review if one line
/// comment is on a line its diff does not show, so these rules are what stand
/// between "Post" and a 422.
@Suite
struct ReviewPlannerTests {
    // Two hunks in args.go: head lines 10–14 and 30–33; base 10–13 and 29–31.
    private static let diff = """
        diff --git a/args.go b/args.go
        --- a/args.go
        +++ b/args.go
        @@ -10,4 +10,5 @@ func A() {
         ten
        -eleven
        +ELEVEN
        +eleven and a half
         twelve
         thirteen
        @@ -29,3 +30,4 @@ func B() {
         thirty
        +thirty-one
         thirty-two
         thirty-three

        """

    private let files = (try? UnifiedDiffParser.parse(diff)) ?? []
    private let pullRequest = PullRequest(
        reference: PullRequestReference(owner: "spf13", repository: "cobra", number: 2397),
        title: "T", body: "", author: "someone", state: .open, isDraft: false,
        base: .init(name: "main", sha: "base-tip"), head: .init(name: "feature", sha: "head-sha")
    )

    private func draft(
        _ side: Side, _ lines: ClosedRange<Int>, body: String = "a note",
        path: String = "args.go", commit: String? = nil, quoted: [String] = ["x"], inPR: Bool = true
    ) -> DraftComment {
        DraftComment(anchor: CommentAnchor(
            path: path, side: side, startLine: lines.lowerBound, endLine: lines.upperBound,
            commit: commit ?? (side == .head ? "head-sha" : "merge-base"),
            quotedLines: quoted, isInPullRequest: inPR
        ), body: body)
    }

    private func plan(_ drafts: [DraftComment], summary: String = "", event: ReviewEvent = .comment,
                      headLines: [String: [String]] = [:]) -> ReviewPlan {
        ReviewPlanner.plan(
            drafts: drafts, summary: summary, event: event, pullRequest: pullRequest,
            mergeBase: "merge-base", files: files, headLines: headLines
        )
    }

    @Test("Puts a head-side line in the diff on the RIGHT")
    func headLine() throws {
        let result = plan([draft(.head, 11...11)])
        #expect(result.items.first?.destination == .line(path: "args.go", side: .head, startLine: nil, line: 11, note: nil))
        let comment = try #require(result.payload.comments.first)
        #expect((comment.path, comment.line, comment.side, comment.startLine) == ("args.go", 11, "RIGHT", nil))
        #expect(result.payload.commitID == "head-sha")
    }

    @Test("Sends a range within one hunk as start_line and line")
    func range() throws {
        let comment = try #require(plan([draft(.head, 11...13)]).payload.comments.first)
        #expect((comment.startLine, comment.line, comment.startSide) == (11, 13, "RIGHT"))
    }

    @Test("Narrows a range that crosses hunks to its last line")
    func crossesHunks() {
        let result = plan([draft(.head, 12...31)])
        #expect(result.items.first?.destination == .line(path: "args.go", side: .head, startLine: nil, line: 31, note: .narrowedToLastLine))
    }

    @Test("Puts a removed line on the LEFT by its base number")
    func baseLine() throws {
        let comment = try #require(plan([draft(.base, 11...11)]).payload.comments.first)
        #expect((comment.line, comment.side) == (11, "LEFT"))
    }

    @Test("Moves a line outside the diff into the summary, quoted and linked")
    func outsideDiff() {
        let result = plan([draft(.head, 20...21, body: "why is this here?", quoted: ["func C() {", "}"])], summary: "Looks good overall.")
        #expect(result.items.first?.destination == .summary(.outsideDiff))
        #expect(result.payload.comments.isEmpty)
        let body = result.payload.body
        #expect(body.hasPrefix("Looks good overall.\n\n---\n\n"))
        #expect(body.contains("**`args.go`** · lines 20–21 ([view](https://github.com/spf13/cobra/blob/head-sha/args.go#L20-L21))"))
        #expect(body.contains("```go\nfunc C() {\n}\n```"))
        #expect(body.hasSuffix("why is this here?"))
    }

    @Test("Moves a base line outside the diff into the summary too")
    func baseOutsideDiff() {
        #expect(plan([draft(.base, 40...40)]).items.first?.destination == .summary(.outsideDiff))
    }

    @Test("Quotes a file outside the PR in the summary, without a link for an absolute path")
    func notInPullRequest() {
        let result = plan([draft(.head, 5...5, path: "/usr/local/go/src/fmt/print.go", inPR: false)])
        #expect(result.items.first?.destination == .summary(.notInPullRequest))
        #expect(!result.payload.body.contains("[view]"))
    }

    @Test("Re-anchors a draft from an older head by its quoted lines")
    func reanchors() {
        // The draft was on lines 3–4 of an older head; the same two lines are
        // now at 12–13, inside the first hunk.
        let current = Array(repeating: "filler", count: 10) + ["ten", "ELEVEN", "eleven and a half", "twelve"]
        let old = draft(.head, 3...4, commit: "old-head", quoted: ["ELEVEN", "eleven and a half"])
        let result = plan([old], headLines: ["args.go": current])
        #expect(result.items.first?.destination == .line(path: "args.go", side: .head, startLine: 12, line: 13, note: .reanchored(fromLine: 3)))
    }

    @Test("Gives up on re-anchoring when the quoted lines appear twice, or not at all")
    func ambiguousReanchor() {
        let twice = ["a", "b", "a", "b"]
        let old = draft(.head, 1...2, commit: "old-head", quoted: ["a", "b"])
        #expect(plan([old], headLines: ["args.go": twice]).items.first?.destination == .summary(.couldNotReanchor))
        #expect(plan([old], headLines: ["args.go": ["z"]]).items.first?.destination == .summary(.couldNotReanchor))
        #expect(plan([old]).payload.body.contains("— on an earlier commit"))
    }

    @Test("Skips drafts that are empty, kept private, or already posted")
    func skips() {
        var excluded = draft(.head, 11...11)
        excluded.isExcludedFromReview = true
        var posted = draft(.head, 12...12)
        posted.posted = DraftComment.Posted(date: .now, reviewURL: nil)
        let result = plan([draft(.head, 13...13, body: "  \n"), excluded, posted])
        #expect(Set(result.items.map(\.destination)) == [.skipped(.empty), .skipped(.excluded), .skipped(.alreadyPosted)])
        #expect(result.payload.comments.isEmpty)
        #expect(result.postedDraftIDs.isEmpty)
    }

    @Test("Leaves the event out for a pending review, and nil fields out of the JSON")
    func pendingJSON() throws {
        let result = plan([draft(.head, 11...11)], event: .pending)
        #expect(result.payload.event == nil)
        let json = String(decoding: try JSONEncoder().encode(result.payload), as: UTF8.self)
        #expect(json.contains(#""commit_id":"head-sha""#))
        #expect(!json.contains("event"))
        #expect(!json.contains("start_line"))
        #expect(plan([draft(.head, 11...11)], event: .requestChanges).payload.event == "REQUEST_CHANGES")
    }

    @Test("Finds quoted lines only when they occur exactly once")
    func reanchorSearch() {
        #expect(ReviewPlanner.reanchor(["b", "c"], in: ["a", "b", "c", "d"]) == 2...3)
        #expect(ReviewPlanner.reanchor(["b"], in: ["b", "x", "b"]) == nil)
        #expect(ReviewPlanner.reanchor([], in: ["a"]) == nil)
        #expect(ReviewPlanner.reanchor(["a", "b", "c"], in: ["a"]) == nil)
    }
}
