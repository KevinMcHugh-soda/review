import Foundation

/// The reviewer's order for one repository's changed files: directories to
/// read first, in order — `db`, then `pkg/sponsor`, then `pkg/admin`.
///
/// A rule can use wildcards: `*` and `?` within one path component, `**` for
/// any number of them — `internal/*/*.yaml` is every API spec under
/// `internal`. A rule also holds everything beneath what it matches.
///
/// A file goes with the most specific rule that holds it, so `pkg/admin`
/// can come before a later `pkg`. Files under no rule go where `*` is, or
/// last without one. Within one place, files keep the order git lists them
/// in, which is alphabetical.
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

    /// The position of the rule a path falls under: the most specific one
    /// that holds it, else `everythingElse`.
    public func rank(of path: String) -> Int {
        let components = path.split(separator: "/").map(String.init)
        var best: (index: Int, specificity: Specificity)?
        for (index, rule) in rules.enumerated() where rule != Self.everythingElse {
            let pattern = rule.split(separator: "/").map(String.init)
            guard Self.holds(pattern[...], components[...]) else { continue }
            let specificity = Specificity(pattern)
            if best.map({ specificity > $0.specificity }) ?? true { best = (index, specificity) }
        }
        return best?.index ?? rules.firstIndex(of: Self.everythingElse) ?? rules.count
    }

    /// Whether `pattern` matches `path`'s leading components — itself, or a
    /// directory above it.
    static func holds(_ pattern: ArraySlice<String>, _ path: ArraySlice<String>) -> Bool {
        guard let first = pattern.first else { return true }
        if first == "**" {
            // Zero or more components, then the rest of the pattern.
            return path.indices.contains { holds(pattern.dropFirst(), path[$0...]) } || holds(pattern.dropFirst(), [])
        }
        guard let component = path.first, fnmatch(first, component, 0) == 0 else { return false }
        return holds(pattern.dropFirst(), path.dropFirst())
    }

    /// More components wins, then more literal characters: `pkg/admin` over
    /// `pkg`, `internal/*/*.yaml` over `internal/*/*`.
    struct Specificity: Comparable {
        let components: Int
        let literals: Int

        init(_ pattern: [String]) {
            components = pattern.count { $0 != "**" }
            literals = pattern.joined().count { !"*?[]".contains($0) }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.components, lhs.literals) < (rhs.components, rhs.literals)
        }
    }

    /// Whether a rule has wildcards, so names a pattern rather than a
    /// directory.
    public static func isPattern(_ rule: String) -> Bool {
        rule.contains { "*?[".contains($0) }
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
