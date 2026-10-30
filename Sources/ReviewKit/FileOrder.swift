import Foundation

/// The reviewer's order for one repository's changed files: directories to
/// read first, in order — `db`, then `pkg/sponsor`, then `pkg/admin`.
///
/// A file goes with the most specific directory that holds it, so `pkg/admin`
/// can come before a later `pkg`. Files under no listed directory go where
/// `*` is, or last without one. Within one place, files keep the order git
/// lists them in, which is alphabetical.
public struct FileOrder: Hashable, Sendable {
    /// Where files under no listed directory go.
    public static let everythingElse = "*"

    /// Directories (or single files), most wanted first, plus at most one
    /// `everythingElse`.
    public let rules: [String]

    public init(rules: [String] = []) {
        var seen: Set<String> = []
        self.rules = rules.map(Self.normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// No rules: files stay in git's order.
    public var isEmpty: Bool { rules.allSatisfy { $0 == Self.everythingElse } }

    /// `items` reordered, stably, by where each one's path falls.
    public func sorted<Item>(_ items: [Item], path: (Item) -> String) -> [Item] {
        guard !isEmpty else { return items }
        return items.enumerated()
            .map { (rank: rank(of: path($0.element)), index: $0.offset, item: $0.element) }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.item)
    }

    /// The position of the rule a path falls under: the longest directory
    /// that holds it, else `everythingElse`.
    public func rank(of path: String) -> Int {
        var best: (index: Int, length: Int)?
        for (index, rule) in rules.enumerated() where rule != Self.everythingElse {
            guard path == rule || path.hasPrefix(rule + "/") else { continue }
            if rule.count > best?.length ?? -1 { best = (index, rule.count) }
        }
        return best?.index ?? rules.firstIndex(of: Self.everythingElse) ?? rules.count
    }

    /// The order with `directory` moved to the front.
    public func putting(first directory: String) -> Self {
        let directory = Self.normalized(directory)
        return Self(rules: [directory] + withEverythingElse.filter { $0 != directory })
    }

    /// The order with `directory` moved after everything else.
    public func putting(last directory: String) -> Self {
        let directory = Self.normalized(directory)
        return Self(rules: withEverythingElse.filter { $0 != directory } + [directory])
    }

    /// The rules with `everythingElse` written out, at the end when absent —
    /// what the editor shows, so a directory can be dragged below it.
    public var withEverythingElse: [String] {
        rules.contains(Self.everythingElse) ? rules : rules + [Self.everythingElse]
    }

    /// `pkg/sponsor/` and ` ./pkg/sponsor ` both mean `pkg/sponsor`.
    static func normalized(_ rule: String) -> String {
        var rule = rule.trimmingCharacters(in: .whitespaces)
        while rule.hasPrefix("./") { rule.removeFirst(2) }
        return rule.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
