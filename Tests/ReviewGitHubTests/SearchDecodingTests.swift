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

    @Test("Changed files by alias, flagging a pull request with more than one page")
    func changedFiles() throws {
        let references = [
            PullRequestReference(owner: "acme", repository: "r", number: 1),
            PullRequestReference(owner: "acme", repository: "r", number: 2),
            PullRequestReference(owner: "acme", repository: "gone", number: 3),
        ]
        let json = #"""
            {"data": {
              "pr0": {"pullRequest": {"files": {"totalCount": 1, "nodes": [{"path": "a.go", "additions": 3, "deletions": 1}]}}},
              "pr1": {"pullRequest": {"files": {"totalCount": 250, "nodes": [{"path": "b.go", "additions": 1, "deletions": 0}]}}},
              "pr2": null
            }}
            """#
        let pages = try GitHubClient.decodeChangedFiles(Data(json.utf8), for: references)
        #expect(pages[references[0]]?.files == [ChangedFileCount(path: "a.go", additions: 3, deletions: 1)])
        #expect(pages[references[0]]?.isComplete == true)
        #expect(pages[references[1]]?.isComplete == false)
        #expect(pages[references[2]] == nil)
        #expect(GitHubClient.changedFilesQuery(references).contains(#"pr2: repository(owner: "acme", name: "gone") { pullRequest(number: 3)"#))
    }

    @Test("REST's tab-separated file list, skipping lines it cannot read")
    func changedFileLines() {
        let files = GitHubClient.decodeChangedFileLines("a.go\t3\t1\nspaced name.go\t0\t2\nbroken\n")
        #expect(files == [
            ChangedFileCount(path: "a.go", additions: 3, deletions: 1),
            ChangedFileCount(path: "spaced name.go", additions: 0, deletions: 2),
        ])
    }

    @Test("A repository without .gitattributes, or one that cannot be seen, has none")
    func gitAttributes() throws {
        let repositories = [RepositoryName(owner: "acme", name: "a"), RepositoryName(owner: "acme", name: "b"), RepositoryName(owner: "acme", name: "c")]
        let json = #"""
            {"data": {"r0": {"object": {"text": "*.pb.go linguist-generated\n"}}, "r1": {"object": null}, "r2": null}}
            """#
        let texts = try GitHubClient.decodeGitAttributes(Data(json.utf8), for: repositories)
        #expect(texts[repositories[0]] == "*.pb.go linguist-generated\n")
        #expect(texts[repositories[1]] == "")
        #expect(texts[repositories[2]] == "")
    }
}
