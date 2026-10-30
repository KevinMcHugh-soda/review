import Foundation

/// Every repository's file order, in one JSON file keyed by `owner/repo`.
public struct FileOrderStore: Sendable {
    public let file: URL

    public init(root: URL) {
        file = root.appendingPathComponent("file-order.json")
    }

    /// Keyed by the lowercased `owner/repo`: GitHub names ignore case.
    public func load() -> [String: FileOrder] {
        guard let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return Dictionary(stored.map { (Self.key($0.key), FileOrder(rules: $0.value)) }) { _, last in last }
    }

    public func order(for repository: String) -> FileOrder {
        load()[Self.key(repository)] ?? FileOrder()
    }

    public func save(_ orders: [String: FileOrder]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stored = orders.filter { !$0.value.isEmpty }.mapValues(\.rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(stored).write(to: file, options: .atomic)
    }

    public static func key(_ repository: String) -> String { repository.lowercased() }
}
