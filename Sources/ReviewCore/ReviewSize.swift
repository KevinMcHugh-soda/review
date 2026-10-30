import Foundation

/// One changed file's line counts, as GitHub reports them for a pull
/// request.
public struct ChangedFileCount: Hashable, Sendable {
    public let path: String
    public let additions: Int
    public let deletions: Int

    public init(path: String, additions: Int, deletions: Int) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
    }
}

/// How much of a pull request is there to read: its lines split into
/// implementation, generated or vendored, tests, and documentation, by
/// harmony's `scripts/pr-line-count.sh` rules, so a one-line OpenAPI change
/// that regenerates two thousand lines reads as one line.
public struct ReviewSize: Hashable, Sendable {
    public enum Category: String, CaseIterable, Hashable, Sendable {
        case implementation, generated, tests, documentation

        public var title: String {
            switch self {
            case .implementation: "Implementation"
            case .generated: "Generated / Vendored"
            case .tests: "Tests"
            case .documentation: "Documentation"
            }
        }
    }

    public struct Tally: Hashable, Sendable {
        public var files = 0
        public var additions = 0
        public var deletions = 0

        public init(files: Int = 0, additions: Int = 0, deletions: Int = 0) {
            self.files = files
            self.additions = additions
            self.deletions = deletions
        }
    }

    public let tallies: [Category: Tally]

    public init(files: [ChangedFileCount], attributes: GitAttributes) {
        tallies = files.reduce(into: [:]) { tallies, file in
            tallies[Self.category(of: file.path, attributes: attributes), default: Tally()].add(file)
        }
    }

    public subscript(category: Category) -> Tally {
        tallies[category] ?? Tally()
    }

    public var total: Tally {
        tallies.values.reduce(into: Tally()) { total, tally in
            total.files += tally.files
            total.additions += tally.additions
            total.deletions += tally.deletions
        }
    }

    /// Generated wins over everything (a generated mock is still generated),
    /// then tests (a fixture `.md` is test data), then documentation.
    public static func category(of path: String, attributes: GitAttributes) -> Category {
        if attributes.isGenerated(path) { return .generated }
        if isTest(path) { return .tests }
        if isDocumentation(path) { return .documentation }
        return .implementation
    }

    private static let testSuffixes = ["_test.go", "_test.sh"]
        + ["test", "spec"].flatMap { kind in ["js", "ts", "jsx", "tsx"].map { ".\(kind).\($0)" } }
    private static let testDirectories: Set = ["test", "tests", "testdata", "__tests__", "__mocks__", "fixtures", "testutil"]
    private static let documentationSuffixes = [".md", ".mdx", ".mdc", ".rst", ".adoc"]
    private static let documentationDirectories: Set = ["doc", "docs"]

    static func isTest(_ path: String) -> Bool {
        testSuffixes.contains { path.hasSuffix($0) } || directories(of: path).contains { testDirectories.contains(String($0)) }
    }

    /// `decisions/` counts only at the root, as in harmony's script.
    static func isDocumentation(_ path: String) -> Bool {
        documentationSuffixes.contains { path.hasSuffix($0) }
            || directories(of: path).contains { documentationDirectories.contains(String($0)) }
            || path.hasPrefix("decisions/")
    }

    /// Every component but the file's own name.
    private static func directories(of path: String) -> ArraySlice<Substring> {
        path.split(separator: "/").dropLast()
    }
}

extension ReviewSize.Tally {
    mutating func add(_ file: ChangedFileCount) {
        files += 1
        additions += file.additions
        deletions += file.deletions
    }
}
