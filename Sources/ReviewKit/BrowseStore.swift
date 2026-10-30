import Foundation
import ReviewCore

/// Where the browser was looking and how it was filtered, so a relaunch comes
/// back to the same search.
public struct BrowseStore: Sendable {
    public struct Saved: Hashable, Sendable, Codable {
        public var scope: BrowseScope?
        public var filter: PullRequestFilter

        public init(scope: BrowseScope? = nil, filter: PullRequestFilter = PullRequestFilter()) {
            self.scope = scope
            self.filter = filter
        }
    }

    public let file: URL

    public init(root: URL) {
        file = root.appendingPathComponent("browse.json")
    }

    /// The defaults when nothing is saved or it cannot be read.
    public func load() -> Saved {
        guard let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode(Saved.self, from: data)
        else { return Saved() }
        return saved
    }

    public func save(_ saved: Saved) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: file, options: .atomic)
    }
}
