import Foundation

/// Names one repository on GitHub: `owner/repo`.
public struct RepositoryName: Hashable, Sendable, Comparable {
    public let owner: String
    public let name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.description.lowercased() < rhs.description.lowercased()
    }
}

extension RepositoryName: CustomStringConvertible {
    /// `owner/repo`, the form `gh --repo` takes.
    public var description: String { "\(owner)/\(name)" }
}

extension RepositoryName: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        do {
            self = try Self(parsing: text)
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not owner/repo: \(text)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension RepositoryName {
    public enum ParseError: Error, Equatable, Sendable {
        case unrecognized(String)
    }

    /// Accepts `owner/repo`, and a repository's URL with or without the
    /// scheme — including a deeper page such as a pull request.
    public init(parsing input: String) throws(ParseError) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var path = trimmed
        if trimmed.contains("github.com") {
            let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
            guard let components = URLComponents(string: withScheme),
                  let host = components.host?.lowercased(),
                  host == "github.com" || host == "www.github.com"
            else { throw .unrecognized(trimmed) }
            path = components.path
        }
        let parts = path.split(separator: "/")
        let isURL = path != trimmed
        guard parts.count == 2 || (isURL && parts.count > 2),
              PullRequestReference.isName(parts[0]), PullRequestReference.isName(parts[1])
        else { throw .unrecognized(trimmed) }
        self.init(owner: String(parts[0]), name: String(parts[1]))
    }
}

extension PullRequestReference {
    public var repositoryName: RepositoryName { RepositoryName(owner: owner, name: repository) }
}
