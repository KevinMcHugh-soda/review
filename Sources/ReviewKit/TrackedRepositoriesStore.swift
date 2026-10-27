import Foundation
import ReviewCore

/// The repositories whose pull requests fill the sidebar's inbox. None
/// tracked means every repository.
public struct TrackedRepositoriesStore: Sendable {
    public let file: URL

    public init(root: URL) {
        file = root.appendingPathComponent("tracked-repositories.json")
    }

    public func load() -> [RepositoryName] {
        guard let data = try? Data(contentsOf: file),
              let names = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        // One unreadable name drops only itself.
        return names.compactMap { try? RepositoryName(parsing: $0) }
    }

    public func save(_ repositories: [RepositoryName]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(repositories.map(\.description)).write(to: file, options: .atomic)
    }
}
