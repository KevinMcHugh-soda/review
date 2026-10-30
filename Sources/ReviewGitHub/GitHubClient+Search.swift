import Foundation
import ReviewCore
import ReviewProcess

extension GitHubClient {
    /// One page of pull requests matching a search query, through GraphQL
    /// rather than `gh search prs`: one request returns review state and size
    /// as well, and a cursor for the next page. The query travels as a
    /// variable, so what the reviewer types can change the search but never
    /// the request.
    public func searchPullRequests(_ query: String, first: Int = 50, after cursor: String? = nil) async throws -> PullRequestSearchPage {
        let request = """
            query($q: String!, $first: Int!, $after: String) {
              search(query: $q, type: ISSUE, first: $first, after: $after) {
                issueCount
                pageInfo { hasNextPage endCursor }
                nodes {
                  ... on PullRequest {
                    number title isDraft state createdAt updatedAt additions deletions reviewDecision headRefOid
                    repository { nameWithOwner }
                    author { login }
                    latestOpinionatedReviews(first: 100) { nodes { state } }
                  }
                }
              }
            }
            """
        var arguments = ["api", "graphql", "-f", "query=\(request)", "-f", "q=\(query)", "-F", "first=\(first)"]
        if let cursor {
            arguments += ["-f", "after=\(cursor)"]
        }
        let output = try await Subprocess.run(gh, arguments, environment: environment, timeout: .seconds(60))
        guard output.succeeded else {
            let detail = [output.stdoutText, output.stderrText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw GitHubError.failed(status: output.status, message: detail)
        }
        do {
            return try Self.decodeSearchPage(output.stdout)
        } catch {
            throw GitHubError.unreadable("\(error)")
        }
    }

    static func decodeSearchPage(_ data: Data) throws -> PullRequestSearchPage {
        struct Response: Decodable {
            struct DataField: Decodable { let search: Search }
            struct Search: Decodable {
                let issueCount: Int
                let pageInfo: PageInfo
                let nodes: [Node?]
            }
            struct PageInfo: Decodable {
                let hasNextPage: Bool
                let endCursor: String?
            }
            /// Every field optional: a search can match something that is not
            /// a pull request, which comes back as `{}`.
            struct Node: Decodable {
                let number: Int?
                let title: String?
                let isDraft: Bool?
                let state: String?
                let createdAt: Date?
                let updatedAt: Date?
                let additions: Int?
                let deletions: Int?
                let reviewDecision: String?
                let headRefOid: String?
                let repository: Repository?
                let author: Author?
                let latestOpinionatedReviews: Reviews?
            }
            struct Repository: Decodable { let nameWithOwner: String }
            struct Author: Decodable { let login: String }
            struct Reviews: Decodable { let nodes: [Review?] }
            struct Review: Decodable { let state: String }
            let data: DataField
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let search = try decoder.decode(Response.self, from: data).data.search
        let listings = search.nodes.compactMap { node -> PullRequestListing? in
            guard let node, let number = node.number, let title = node.title, let repository = node.repository,
                  let createdAt = node.createdAt, let updatedAt = node.updatedAt,
                  let reference = try? PullRequestReference(parsing: "\(repository.nameWithOwner)#\(number)")
            else { return nil }
            let status: PullRequestStatus = switch node.state {
            case "MERGED": .merged
            case "CLOSED": .closed
            default: node.isDraft == true ? .draft : .open
            }
            let reviews = node.latestOpinionatedReviews?.nodes.compactMap { $0?.state } ?? []
            return PullRequestListing(
                reference: reference, title: title, author: node.author?.login ?? "ghost", status: status,
                createdAt: createdAt, updatedAt: updatedAt,
                additions: node.additions ?? 0, deletions: node.deletions ?? 0,
                reviewState: reviewState(decision: node.reviewDecision, reviews: reviews),
                headSHA: node.headRefOid
            )
        }
        return PullRequestSearchPage(
            listings: listings,
            totalCount: search.issueCount,
            nextCursor: search.pageInfo.hasNextPage ? search.pageInfo.endCursor : nil
        )
    }

    /// `reviewDecision` is null where the repository does not require
    /// reviews; then any reviewer asking for changes outweighs approvals.
    static func reviewState(decision: String?, reviews: [String]) -> PullRequestListing.ReviewState? {
        switch decision {
        case "APPROVED": return .approved
        case "CHANGES_REQUESTED": return .changesRequested
        case "REVIEW_REQUIRED": return .reviewRequired
        default: break
        }
        if reviews.contains("CHANGES_REQUESTED") { return .changesRequested }
        if reviews.contains("APPROVED") { return .approved }
        return nil
    }

    /// Repositories the viewer owns, collaborates on, or can see through an
    /// organization, most recently pushed first, archived ones left out.
    /// REST rather than GraphQL: GraphQL's `viewer.repositories` misses
    /// repositories reached through an organization's teams.
    public func repositories() async throws -> [RepositoryName] {
        let output = try await Subprocess.run(
            gh,
            [
                "api", "--paginate",
                "user/repos?per_page=100&sort=pushed&affiliation=owner,collaborator,organization_member",
                "--jq", ".[] | select(.archived | not) | .full_name",
            ],
            environment: environment,
            timeout: .seconds(120)
        )
        guard output.succeeded else {
            throw GitHubError.failed(status: output.status, message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Self.decodeRepositoryNames(output.stdoutText)
    }

    /// One `owner/repo` per line; duplicates (a page boundary that moved
    /// while paging) and anything unreadable are dropped.
    static func decodeRepositoryNames(_ text: String) -> [RepositoryName] {
        var seen: Set<RepositoryName> = []
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let name = try? RepositoryName(parsing: String(line)), seen.insert(name).inserted else { return nil }
            return name
        }
    }
}
