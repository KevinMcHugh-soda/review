import Foundation

/// Names one pull request on GitHub: `owner/repo#123`.
///
/// Parsed from whatever a reviewer is likely to paste — the PR's URL (including
/// the `/files` and `/commits` tabs), or the `owner/repo#123` shorthand that
/// `gh` and GitHub itself use.
public struct PullRequestReference: Hashable, Sendable, Codable {
    public let owner: String
    public let repository: String
    public let number: Int

    public init(owner: String, repository: String, number: Int) {
        self.owner = owner
        self.repository = repository
        self.number = number
    }

    /// `owner/repo`, the form `gh --repo` takes.
    public var repositorySlug: String { "\(owner)/\(repository)" }

    public var webURL: URL {
        URL(string: "https://github.com/\(owner)/\(repository)/pull/\(number)")!
    }
}

extension PullRequestReference: CustomStringConvertible {
    public var description: String { "\(repositorySlug)#\(number)" }
}

extension PullRequestReference {
    public enum ParseError: Error, Equatable, Sendable {
        case unrecognized(String)
    }

    /// Accepts `https://github.com/o/r/pull/12`, the same with a trailing
    /// tab, query or fragment, `github.com/o/r/pull/12` without a scheme,
    /// and `o/r#12`.
    public init(parsing input: String) throws(ParseError) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let reference = Self.shorthand(trimmed) ?? Self.url(trimmed) {
            self = reference
        } else {
            throw .unrecognized(trimmed)
        }
    }

    private static func shorthand(_ input: String) -> Self? {
        let parts = input.split(separator: "#", omittingEmptySubsequences: false)
        guard parts.count == 2, let number = Int(parts[1]), number > 0 else { return nil }
        let slug = parts[0].split(separator: "/", omittingEmptySubsequences: false)
        guard slug.count == 2, isName(slug[0]), isName(slug[1]) else { return nil }
        return Self(owner: String(slug[0]), repository: String(slug[1]), number: number)
    }

    private static func url(_ input: String) -> Self? {
        let withScheme = input.contains("://") ? input : "https://\(input)"
        guard
            let components = URLComponents(string: withScheme),
            let host = components.host?.lowercased(),
            host == "github.com" || host == "www.github.com"
        else { return nil }

        // ["", owner, repo, "pull", number, maybe "files"...]
        let path = components.path.split(separator: "/")
        guard
            path.count >= 4,
            path[2] == "pull",
            isName(path[0]), isName(path[1]),
            let number = Int(path[3]), number > 0
        else { return nil }
        return Self(owner: String(path[0]), repository: String(path[1]), number: number)
    }

    /// GitHub owner and repository names: letters, digits, `-`, `_` and `.`.
    private static func isName(_ part: Substring) -> Bool {
        !part.isEmpty
            && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }
}
