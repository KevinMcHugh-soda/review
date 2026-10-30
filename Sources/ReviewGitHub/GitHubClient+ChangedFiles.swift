import Foundation
import ReviewCore
import ReviewProcess

extension GitHubClient {
    /// Every changed file's line counts, for each pull request: one GraphQL
    /// request per 25 — an alias each — for the first 100 files, then REST
    /// for the rest of any larger one, which is usually the generated kind.
    /// A pull request that cannot be seen is left out.
    public func changedFiles(of references: [PullRequestReference]) async throws -> [PullRequestReference: [ChangedFileCount]] {
        var files: [PullRequestReference: [ChangedFileCount]] = [:]
        for start in stride(from: 0, to: references.count, by: 25) {
            let chunk = Array(references[start..<min(start + 25, references.count)])
            let output = try await Subprocess.run(
                gh,
                ["api", "graphql", "-f", "query=\(Self.changedFilesQuery(chunk))"],
                environment: environment,
                timeout: .seconds(60)
            )
            // GitHub answers partially when one PR cannot be seen, and gh
            // calls that a failure while still printing the data.
            guard let decoded = try? Self.decodeChangedFiles(output.stdout, for: chunk) else {
                throw GitHubError.failed(status: output.status, message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            for (reference, page) in decoded {
                files[reference] = page.isComplete ? page.files : try await allChangedFiles(reference)
            }
        }
        return files
    }

    struct ChangedFilesPage {
        let files: [ChangedFileCount]
        let isComplete: Bool
    }

    /// Owner and repository names are only letters, digits, `-`, `_` and `.`
    /// (`PullRequestReference` checks), so they are safe inside the quotes.
    static func changedFilesQuery(_ references: [PullRequestReference]) -> String {
        let fields = references.enumerated().map { index, reference in
            #"pr\#(index): repository(owner: "\#(reference.owner)", name: "\#(reference.repository)") { pullRequest(number: \#(reference.number)) { files(first: 100) { totalCount nodes { path additions deletions } } } }"#
        }
        return "query {\n\(fields.joined(separator: "\n"))\n}"
    }

    static func decodeChangedFiles(_ data: Data, for references: [PullRequestReference]) throws -> [PullRequestReference: ChangedFilesPage] {
        struct Response: Decodable {
            struct Repository: Decodable { let pullRequest: PullRequestField? }
            struct PullRequestField: Decodable { let files: Files? }
            struct Files: Decodable {
                let totalCount: Int
                let nodes: [File]
            }
            struct File: Decodable {
                let path: String
                let additions: Int
                let deletions: Int
            }
            let data: [String: Repository?]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let pairs = references.enumerated().compactMap { index, reference -> (PullRequestReference, ChangedFilesPage)? in
            guard let files = response.data["pr\(index)"].flatMap({ $0 })?.pullRequest?.files else { return nil }
            let counts = files.nodes.map { ChangedFileCount(path: $0.path, additions: $0.additions, deletions: $0.deletions) }
            return (reference, ChangedFilesPage(files: counts, isComplete: counts.count >= files.totalCount))
        }
        return Dictionary(pairs) { _, new in new }
    }

    /// REST pages through up to 3,000 files, GitHub's limit for this list.
    private func allChangedFiles(_ reference: PullRequestReference) async throws -> [ChangedFileCount] {
        let output = try await Subprocess.run(
            gh,
            [
                "api", "--paginate", "repos/\(reference.repositorySlug)/pulls/\(reference.number)/files?per_page=100",
                "--jq", ".[] | [.filename, .additions, .deletions] | @tsv",
            ],
            environment: environment,
            timeout: .seconds(120)
        )
        guard output.succeeded else {
            throw GitHubError.failed(status: output.status, message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Self.decodeChangedFileLines(output.stdoutText)
    }

    /// `path<TAB>additions<TAB>deletions` per line.
    static func decodeChangedFileLines(_ text: String) -> [ChangedFileCount] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, let additions = Int(fields[1]), let deletions = Int(fields[2]) else { return nil }
            return ChangedFileCount(path: String(fields[0]), additions: additions, deletions: deletions)
        }
    }

    /// Each repository's root `.gitattributes` on its default branch, in one
    /// request; empty when it has none or cannot be seen.
    public func gitAttributes(of repositories: [RepositoryName]) async throws -> [RepositoryName: String] {
        guard !repositories.isEmpty else { return [:] }
        let output = try await Subprocess.run(
            gh,
            ["api", "graphql", "-f", "query=\(Self.gitAttributesQuery(repositories))"],
            environment: environment,
            timeout: .seconds(60)
        )
        guard let decoded = try? Self.decodeGitAttributes(output.stdout, for: repositories) else {
            throw GitHubError.failed(status: output.status, message: output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return decoded
    }

    static func gitAttributesQuery(_ repositories: [RepositoryName]) -> String {
        let fields = repositories.enumerated().map { index, repository in
            #"r\#(index): repository(owner: "\#(repository.owner)", name: "\#(repository.name)") { object(expression: "HEAD:.gitattributes") { ... on Blob { text } } }"#
        }
        return "query {\n\(fields.joined(separator: "\n"))\n}"
    }

    static func decodeGitAttributes(_ data: Data, for repositories: [RepositoryName]) throws -> [RepositoryName: String] {
        struct Response: Decodable {
            struct Repository: Decodable { let object: Blob? }
            struct Blob: Decodable { let text: String? }
            let data: [String: Repository?]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let pairs = repositories.enumerated().map { index, repository in
            (repository, response.data["r\(index)"].flatMap { $0 }?.object?.text ?? "")
        }
        return Dictionary(pairs) { _, new in new }
    }
}
