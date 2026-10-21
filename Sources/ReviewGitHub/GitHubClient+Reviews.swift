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
    /// Open pull requests the viewer is asked to review, is assigned, or
    /// wrote — one search each, merged — newest activity first. Limited to
    /// `repositories` unless it is empty, which means all of GitHub.
    public func inbox(in repositories: [RepositoryName], limit: Int = 100) async throws -> [InboxItem] {
        try await withThrowingTaskGroup(of: [InboxItem].self) { group in
            for reason in InboxItem.Reason.allCases {
                group.addTask { try await self.search(reason, in: repositories, limit: limit) }
            }
            return try await group.reduce(into: []) { $0 += $1 }.mergingReasons()
        }
    }

    private func search(_ reason: InboxItem.Reason, in repositories: [RepositoryName], limit: Int) async throws -> [InboxItem] {
        let output = try await Subprocess.run(
            gh,
            Self.searchArguments(reason, in: repositories, limit: limit),
            environment: environment,
            timeout: .seconds(60)
        )
        guard output.succeeded else {
            throw GitHubError.failed(status: output.status, message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        do {
            return try Self.decodeInbox(output.stdout, reason: reason)
        } catch {
            throw GitHubError.unreadable("\(error)")
        }
    }

    /// `--repo` may repeat; GitHub ORs the repositories and ANDs the rest.
    static func searchArguments(_ reason: InboxItem.Reason, in repositories: [RepositoryName], limit: Int) -> [String] {
        let qualifier = switch reason {
        case .reviewRequested: "--review-requested=@me"
        case .assigned: "--assignee=@me"
        case .authored: "--author=@me"
        }
        return ["search", "prs", qualifier, "--state=open", "--limit", String(limit)]
            + repositories.flatMap { ["--repo", $0.description] }
            + ["--json", "number,title,repository,author,updatedAt,isDraft"]
    }

    static func decodeInbox(_ data: Data, reason: InboxItem.Reason = .reviewRequested) throws -> [InboxItem] {
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
                    isDraft: result.isDraft, updatedAt: result.updatedAt, reasons: [reason]
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

extension GitHubClient {
    /// Replies to an existing thread. Posted at once, as on GitHub's own
    /// "Reply" button — not added to a pending review.
    public func reply(toThread threadID: String, body: String) async throws {
        try await graphQL(
            """
            mutation($thread: ID!, $body: String!) {
              addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: $thread, body: $body }) {
                comment { id }
              }
            }
            """,
            variables: ["thread": threadID, "body": body]
        )
    }

    public func setResolved(_ isResolved: Bool, thread threadID: String) async throws {
        let mutation = isResolved ? "resolveReviewThread" : "unresolveReviewThread"
        try await graphQL(
            """
            mutation($thread: ID!) {
              \(mutation)(input: { threadId: $thread }) { thread { id isResolved } }
            }
            """,
            variables: ["thread": threadID]
        )
    }

    /// A GraphQL request whose variables are all strings (`-f`, so a body that
    /// looks like a number or `true` is never retyped). GitHub reports
    /// GraphQL failures as `errors` in a 200 response, which `gh` turns into a
    /// non-zero exit.
    private func graphQL(_ query: String, variables: [String: String]) async throws {
        var arguments = ["api", "graphql", "-f", "query=\(query)"]
        for (name, value) in variables.sorted(by: { $0.key < $1.key }) {
            arguments += ["-f", "\(name)=\(value)"]
        }
        let output = try await Subprocess.run(gh, arguments, environment: environment, timeout: .seconds(60))
        guard output.succeeded else {
            let detail = [output.stdoutText, output.stderrText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw GitHubError.failed(status: output.status, message: detail)
        }
    }
}
