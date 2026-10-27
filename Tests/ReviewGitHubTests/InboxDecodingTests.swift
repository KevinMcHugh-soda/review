import Foundation
import ReviewCore
import Testing
@testable import ReviewGitHub

@Suite
struct InboxDecodingTests {
    /// The shape of `gh search prs --json number,title,repository,author,updatedAt,isDraft`.
    @Test("Decodes review requests newest first, tolerating a deleted author")
    func decodes() throws {
        let json = #"""
            [
              {"number": 12, "title": "Older", "repository": {"name": "r", "nameWithOwner": "acme/r"},
               "author": {"login": "dev", "is_bot": false}, "updatedAt": "2026-09-01T00:00:00Z", "isDraft": false},
              {"number": 13, "title": "Newer", "repository": {"name": "r", "nameWithOwner": "acme/r"},
               "author": null, "updatedAt": "2026-10-01T00:00:00Z", "isDraft": true}
            ]
            """#
        let items = try GitHubClient.decodeInbox(Data(json.utf8))
        #expect(items.map(\.title) == ["Newer", "Older"])
        #expect(items[0].reference == PullRequestReference(owner: "acme", repository: "r", number: 13))
        #expect(items[0].author == "ghost")
        #expect(items[0].isDraft)
    }

    @Test("Tags each decoded item with the search it came from")
    func tagsReason() throws {
        let json = #"""
            [{"number": 1, "title": "Mine", "repository": {"nameWithOwner": "acme/r"},
              "author": {"login": "me"}, "updatedAt": "2026-09-01T00:00:00Z", "isDraft": false}]
            """#
        let items = try GitHubClient.decodeInbox(Data(json.utf8), reason: .authored)
        #expect(items.first?.reasons == [.authored])
    }

    @Test("Searches each tracked repository, or everywhere when none are tracked")
    func arguments() {
        let repositories = [RepositoryName(owner: "acme", name: "a"), RepositoryName(owner: "acme", name: "b")]
        let tracked = GitHubClient.searchArguments(.assigned, in: repositories, limit: 100)
        #expect(tracked.starts(with: ["search", "prs", "--assignee=@me", "--state=open"]))
        #expect(tracked.contains(["--repo", "acme/a", "--repo", "acme/b"]))
        let everywhere = GitHubClient.searchArguments(.reviewRequested, in: [], limit: 100)
        #expect(everywhere.contains("--review-requested=@me"))
        #expect(!everywhere.contains("--repo"))
        #expect(GitHubClient.searchArguments(.authored, in: [], limit: 100).contains("--author=@me"))
    }
}
