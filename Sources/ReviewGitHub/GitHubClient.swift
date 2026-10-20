import Foundation
import ReviewCore
import ReviewProcess

public enum GitHubError: Error, Sendable, CustomStringConvertible, Equatable {
    case notFound(PullRequestReference)
    case failed(status: Int32, message: String)
    case unreadable(String)

    public var description: String {
        switch self {
        case .notFound(let reference):
            "\(reference) was not found, or this gh account cannot see it."
        case let .failed(status, message):
            "gh failed (\(status)): \(message)"
        case .unreadable(let detail):
            "GitHub's response could not be read: \(detail)"
        }
    }
}

/// GitHub through `gh api`. The reviewer's `gh` login supplies the
/// credentials; this type never sees a token.
public struct GitHubClient: Sendable {
    let gh: URL
    let environment: [String: String]

    public init(gh: URL, environment: [String: String]) {
        self.gh = gh
        var environment = environment
        // Plain output, no pager, no update nag on stderr.
        environment["GH_PAGER"] = ""
        environment["NO_COLOR"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        self.environment = environment
    }

    public func pullRequest(_ reference: PullRequestReference) async throws -> PullRequest {
        let data = try await api("repos/\(reference.repositorySlug)/pulls/\(reference.number)", reference: reference)
        do {
            let response = try JSONDecoder().decode(PullResponse.self, from: data)
            return response.pullRequest(reference)
        } catch {
            throw GitHubError.unreadable("\(error)")
        }
    }

    func api(_ path: String, reference: PullRequestReference) async throws -> Data {
        let output = try await Subprocess.run(gh, ["api", path], environment: environment, timeout: .seconds(60))
        guard output.succeeded else {
            if output.stderrText.contains("HTTP 404") { throw GitHubError.notFound(reference) }
            throw GitHubError.failed(
                status: output.status,
                message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output.stdout
    }
}

/// The parts of `GET /repos/{o}/{r}/pulls/{n}` this app reads.
struct PullResponse: Decodable {
    struct User: Decodable {
        let login: String
    }

    struct Ref: Decodable {
        let ref: String
        let sha: String
    }

    let title: String
    let body: String?
    let user: User
    let state: String
    let merged: Bool?
    let draft: Bool?
    let base: Ref
    let head: Ref

    func pullRequest(_ reference: PullRequestReference) -> PullRequest {
        let state: PullRequest.State = if merged == true { .merged } else if self.state == "closed" { .closed } else { .open }
        return PullRequest(
            reference: reference,
            title: title,
            body: body ?? "",
            author: user.login,
            state: state,
            isDraft: draft ?? false,
            base: PullRequest.Branch(name: base.ref, sha: base.sha),
            head: PullRequest.Branch(name: head.ref, sha: head.sha)
        )
    }
}
