import Foundation
import ReviewCore
import Testing
@testable import ReviewGitHub

@Suite
struct SearchDecodingTests {
    /// The shape of the browser's GraphQL `search`, cut down from a real
    /// response.
    @Test("Decodes a page of pull requests, skipping matches that are not pull requests")
    func decodesPage() throws {
        let json = #"""
            {"data": {"search": {
              "issueCount": 120,
              "pageInfo": {"hasNextPage": true, "endCursor": "Y3Vyc29yOjUw"},
              "nodes": [
                {"number": 15273, "title": "List a member's funding transactions", "isDraft": false, "state": "OPEN",
                 "createdAt": "2026-10-30T01:34:06Z", "updatedAt": "2026-10-30T21:38:21Z",
                 "additions": 805, "deletions": 50, "reviewDecision": "REVIEW_REQUIRED",
                 "repository": {"nameWithOwner": "sodahealth/harmony"}, "author": {"login": "dev"},
                 "latestOpinionatedReviews": {"nodes": []}},
                {},
                {"number": 7, "title": "Draft", "isDraft": true, "state": "OPEN",
                 "createdAt": "2026-10-01T00:00:00Z", "updatedAt": "2026-10-02T00:00:00Z",
                 "additions": 1, "deletions": 0, "reviewDecision": null,
                 "repository": {"nameWithOwner": "acme/r"}, "author": null,
                 "latestOpinionatedReviews": {"nodes": [{"state": "APPROVED"}]}},
                {"number": 8, "title": "Merged", "isDraft": false, "state": "MERGED",
                 "createdAt": "2026-09-01T00:00:00Z", "updatedAt": "2026-09-02T00:00:00Z",
                 "additions": 0, "deletions": 3, "reviewDecision": null,
                 "repository": {"nameWithOwner": "acme/r"}, "author": {"login": "dev"},
                 "latestOpinionatedReviews": {"nodes": [{"state": "APPROVED"}, {"state": "CHANGES_REQUESTED"}]}}
              ]
            }}}
            """#
        let page = try GitHubClient.decodeSearchPage(Data(json.utf8))
        #expect(page.totalCount == 120)
        #expect(page.nextCursor == "Y3Vyc29yOjUw")
        #expect(page.listings.map(\.reference.description) == ["sodahealth/harmony#15273", "acme/r#7", "acme/r#8"])
        #expect(page.listings.map(\.status) == [.open, .draft, .merged])
        #expect(page.listings.map(\.reviewState) == [.reviewRequired, .approved, .changesRequested])
        #expect(page.listings[1].author == "ghost")
        #expect(page.listings[0].additions == 805 && page.listings[0].deletions == 50)
    }

    @Test("The last page has no cursor to follow")
    func lastPage() throws {
        let json = #"""
            {"data": {"search": {"issueCount": 0, "pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": []}}}
            """#
        let page = try GitHubClient.decodeSearchPage(Data(json.utf8))
        #expect(page.nextCursor == nil)
        #expect(page.listings.isEmpty)
    }

    @Test("GitHub's decision wins over individual reviews when it has one")
    func reviewState() {
        #expect(GitHubClient.reviewState(decision: "APPROVED", reviews: ["CHANGES_REQUESTED"]) == .approved)
        #expect(GitHubClient.reviewState(decision: nil, reviews: ["COMMENTED"]) == nil)
        #expect(GitHubClient.reviewState(decision: nil, reviews: []) == nil)
    }

    @Test("Repository names: one per line, duplicates and junk dropped, order kept")
    func repositoryNames() {
        let names = GitHubClient.decodeRepositoryNames("sodahealth/k8s-flux\nsodahealth/harmony\n\nnot a repo\nsodahealth/k8s-flux\n")
        #expect(names.map(\.description) == ["sodahealth/k8s-flux", "sodahealth/harmony"])
    }
}
