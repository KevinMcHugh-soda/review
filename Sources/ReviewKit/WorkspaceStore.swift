import Foundation
import ReviewCore

/// Which pull requests are open in the sidebar, so a relaunch brings them
/// back in the same order.
public struct WorkspaceStore: Sendable {
    public let file: URL

    public init(root: URL) {
        file = root.appendingPathComponent("open-pull-requests.json")
    }

    public func load() -> [PullRequestReference] {
        guard let data = try? Data(contentsOf: file),
              let names = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return names.compactMap { try? PullRequestReference(parsing: $0) }
    }

    public func save(_ references: [PullRequestReference]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(references.map(\.description)).write(to: file, options: .atomic)
    }
}
