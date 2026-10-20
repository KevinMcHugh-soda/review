import Foundation
import ReviewCore
import ReviewProcess

extension GitHubClient {
    /// The login `gh` is signed in as.
    public func viewerLogin() async throws -> String {
        let output = try await Subprocess.run(gh, ["api", "user", "--jq", ".login"], environment: environment, timeout: .seconds(30))
        guard output.succeeded else {
            throw GitHubError.failed(status: output.status, message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every review thread on the PR, through GraphQL: REST has no resolved
    /// flag. Paginated by `gh --paginate --slurp`, which needs the cursor
    /// variable to be called `$endCursor`.
    public func reviewThreads(_ reference: PullRequestReference) async throws -> [ReviewThread] {
        let query = """
            query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
              repository(owner: $owner, name: $repo) {
                pullRequest(number: $number) {
                  reviewThreads(first: 100, after: $endCursor) {
                    pageInfo { hasNextPage endCursor }
                    nodes {
                      id isResolved isOutdated path line startLine originalLine diffSide
                      comments(first: 100) { nodes { author { login } body createdAt url } }
                    }
                  }
                }
              }
            }
            """
        let output = try await Subprocess.run(
            gh,
            [
                "api", "graphql", "--paginate", "--slurp",
                "-f", "query=\(query)",
                "-F", "owner=\(reference.owner)", "-F", "repo=\(reference.repository)", "-F", "number=\(reference.number)",
            ],
            environment: environment,
            timeout: .seconds(60)
        )
        guard output.succeeded else {
            throw GitHubError.failed(status: output.status, message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        do {
            return try Self.decodeThreads(output.stdout)
        } catch {
            throw GitHubError.unreadable("\(error)")
        }
    }

    static func decodeThreads(_ data: Data) throws -> [ReviewThread] {
        struct Page: Decodable {
            struct DataField: Decodable { let repository: Repository }
            struct Repository: Decodable { let pullRequest: PullRequestField }
            struct PullRequestField: Decodable { let reviewThreads: Threads }
            struct Threads: Decodable { let nodes: [Node] }
            struct Node: Decodable {
                let id: String
                let isResolved: Bool
                let isOutdated: Bool
                let path: String
                let line: Int?
                let startLine: Int?
                let originalLine: Int?
                let diffSide: String
                let comments: Comments
            }
            struct Comments: Decodable { let nodes: [Comment] }
            struct Comment: Decodable {
                struct Author: Decodable { let login: String }
                // Null for a deleted ("ghost") account.
                let author: Author?
                let body: String
                let createdAt: Date
                let url: URL?
            }
            let data: DataField
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Page].self, from: data)
            .flatMap(\.data.repository.pullRequest.reviewThreads.nodes)
            .map { node in
                ReviewThread(
                    id: node.id, path: node.path, side: node.diffSide == "LEFT" ? .base : .head,
                    line: node.line, startLine: node.startLine, originalLine: node.originalLine,
                    isResolved: node.isResolved, isOutdated: node.isOutdated,
                    comments: node.comments.nodes.map {
                        ThreadComment(author: $0.author?.login ?? "ghost", body: $0.body, createdAt: $0.createdAt, url: $0.url)
                    }
                )
            }
    }

    /// The viewer's unsubmitted review on this PR, if any. GitHub allows one;
    /// creating a second fails.
    public func pendingReviewURL(_ reference: PullRequestReference, viewer: String) async throws -> URL? {
        let output = try await Subprocess.run(
            gh,
            [
                "api", "--paginate",
                "repos/\(reference.repositorySlug)/pulls/\(reference.number)/reviews",
                "--jq", ".[] | select(.state == \"PENDING\" and .user.login == \"\(viewer)\") | .html_url",
            ],
            environment: environment,
            timeout: .seconds(60)
        )
        guard output.succeeded else {
            throw GitHubError.failed(status: output.status, message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output.stdoutText.split(whereSeparator: \.isNewline).first.flatMap { URL(string: String($0)) }
    }

    /// Creates the review — every line comment and the summary in one request,
    /// so it either all lands or none of it does. Returns the review's page.
    public func createReview(_ reference: PullRequestReference, payload: some Encodable) async throws -> URL? {
        let output = try await Subprocess.run(
            gh,
            ["api", "--method", "POST", "repos/\(reference.repositorySlug)/pulls/\(reference.number)/reviews", "--input", "-"],
            environment: environment,
            input: try JSONEncoder().encode(payload),
            timeout: .seconds(120)
        )
        guard output.succeeded else {
            // gh prints GitHub's JSON error on stdout and a summary on stderr;
            // the JSON says which comment was refused.
            let detail = [output.stdoutText, output.stderrText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw GitHubError.failed(status: output.status, message: detail)
        }
        return (try? JSONDecoder().decode(CreatedReview.self, from: output.stdout))?.htmlURL
    }
}

/// The part of the created review this app reads.
private struct CreatedReview: Decodable {
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case htmlURL = "html_url"
    }
}

extension GitHubClient {
    /// Open pull requests where the viewer's review is requested, newest
    /// activity first.
    public func reviewRequests(limit: Int = 50) async throws -> [InboxItem] {
        let output = try await Subprocess.run(
            gh,
            [
                "search", "prs", "--review-requested=@me", "--state=open", "--limit", String(limit),
                "--json", "number,title,repository,author,updatedAt,isDraft",
            ],
            environment: environment,
            timeout: .seconds(60)
        )
        guard output.succeeded else {
            throw GitHubError.failed(status: output.status, message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        do {
            return try Self.decodeInbox(output.stdout)
        } catch {
            throw GitHubError.unreadable("\(error)")
        }
    }

    static func decodeInbox(_ data: Data) throws -> [InboxItem] {
        struct Result: Decodable {
            struct Repository: Decodable { let nameWithOwner: String }
            struct Author: Decodable { let login: String }
            let number: Int
            let title: String
            let repository: Repository
            let author: Author?
            let updatedAt: Date
            let isDraft: Bool
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Result].self, from: data)
            .compactMap { result in
                guard let reference = try? PullRequestReference(parsing: "\(result.repository.nameWithOwner)#\(result.number)") else {
                    return nil
                }
                return InboxItem(
                    reference: reference, title: result.title, author: result.author?.login ?? "ghost",
                    isDraft: result.isDraft, updatedAt: result.updatedAt
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
