import Foundation
import ReviewCore
import ReviewProcess

extension GitHubClient {
    /// The title and status of each pull request, in one GraphQL request per
    /// fifty — an alias per PR, since GraphQL has no "these PRs" lookup.
    /// One PR that cannot be seen leaves the rest: GitHub answers with partial
    /// data and an error, which `gh` reports as a failure but still prints.
    public func summaries(of references: [PullRequestReference]) async throws -> [PullRequestReference: PullRequestSummary] {
        var summaries: [PullRequestReference: PullRequestSummary] = [:]
        for start in stride(from: 0, to: references.count, by: 50) {
            let chunk = Array(references[start..<min(start + 50, references.count)])
            let output = try await Subprocess.run(
                gh,
                ["api", "graphql", "-f", "query=\(Self.summariesQuery(chunk))"],
                environment: environment,
                timeout: .seconds(60)
            )
            guard let decoded = try? Self.decodeSummaries(output.stdout, for: chunk) else {
                throw GitHubError.failed(status: output.status, message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            summaries.merge(decoded) { _, new in new }
        }
        return summaries
    }

    /// Owner and repository names are only letters, digits, `-`, `_` and `.`
    /// (`PullRequestReference` checks), so they are safe inside the quotes.
    static func summariesQuery(_ references: [PullRequestReference]) -> String {
        let fields = references.enumerated().map { index, reference in
            #"pr\#(index): repository(owner: "\#(reference.owner)", name: "\#(reference.repository)") { pullRequest(number: \#(reference.number)) { title state isDraft } }"#
        }
        return "query {\n\(fields.joined(separator: "\n"))\n}"
    }

    static func decodeSummaries(
        _ data: Data,
        for references: [PullRequestReference]
    ) throws -> [PullRequestReference: PullRequestSummary] {
        struct Response: Decodable {
            struct Repository: Decodable { let pullRequest: Node? }
            struct Node: Decodable {
                let title: String
                let state: String
                let isDraft: Bool
            }
            let data: [String: Repository?]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let pairs = references.enumerated().compactMap { index, reference -> (PullRequestReference, PullRequestSummary)? in
            guard let node = response.data["pr\(index)"].flatMap({ $0 })?.pullRequest else { return nil }
            let status: PullRequestStatus = switch node.state {
            case "MERGED": .merged
            case "CLOSED": .closed
            default: node.isDraft ? .draft : .open
            }
            return (reference, PullRequestSummary(reference: reference, title: node.title, status: status))
        }
        return Dictionary(pairs) { _, new in new }
    }
}
