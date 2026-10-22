import Foundation
import ReviewCore
import Testing
@testable import ReviewGitHub

@Suite
struct SummaryDecodingTests {
    private let references = [
        PullRequestReference(owner: "acme", repository: "r", number: 1),
        PullRequestReference(owner: "acme", repository: "r", number: 2),
        PullRequestReference(owner: "acme", repository: "r", number: 3),
        PullRequestReference(owner: "acme", repository: "gone", number: 4),
    ]

    /// GitHub's answer when one repository cannot be seen: null under its
    /// alias, beside an `errors` array.
    @Test("Decodes each alias's status and skips the ones GitHub could not resolve")
    func decodes() throws {
        let json = #"""
            {"data": {
              "pr0": {"pullRequest": {"title": "Ready", "state": "OPEN", "isDraft": false, "author": {"login": "dev"},
                "latestOpinionatedReviews": {"nodes": [{"state": "CHANGES_REQUESTED"}, {"state": "APPROVED"}]}}},
              "pr1": {"pullRequest": {"title": "WIP", "state": "OPEN", "isDraft": true,
                "latestOpinionatedReviews": {"nodes": [{"state": "CHANGES_REQUESTED"}]}}},
              "pr2": {"pullRequest": {"title": "Done", "state": "MERGED", "isDraft": false}},
              "pr3": null
            },
            "errors": [{"type": "NOT_FOUND", "path": ["pr3"], "message": "Could not resolve"}]}
            """#
        let summaries = try GitHubClient.decodeSummaries(Data(json.utf8), for: references)
        #expect(summaries[references[0]]?.status == .open)
        #expect(summaries[references[0]]?.author == "dev")
        #expect(summaries[references[0]]?.isApproved == true)
        #expect(summaries[references[1]]?.isApproved == false)
        #expect(summaries[references[2]]?.isApproved == false)
        #expect(summaries[references[1]]?.author == "ghost")
        #expect(summaries[references[1]]?.status == .draft)
        #expect(summaries[references[2]]?.status == .merged)
        #expect(summaries[references[2]]?.title == "Done")
        #expect(summaries[references[3]] == nil)
    }

    @Test("Asks for every pull request under its own alias")
    func query() {
        let query = GitHubClient.summariesQuery(Array(references.prefix(2)))
        #expect(query.contains(#"pr0: repository(owner: "acme", name: "r") { pullRequest(number: 1)"#))
        #expect(query.contains("pr1: "))
        #expect(query.contains("latestOpinionatedReviews"))
    }
}
