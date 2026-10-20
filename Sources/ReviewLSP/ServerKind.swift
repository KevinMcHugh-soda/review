import Foundation

/// The two language servers this app drives.
public enum ServerKind: String, Hashable, Sendable, CaseIterable {
    case go
    /// TypeScript and JavaScript alike: one project covers both. Served by
    /// TypeScript 7's own server or typescript-language-server; see
    /// `ServerCommand`.
    case typeScript

    /// For messages; which program actually runs is `ServerCommand`'s call.
    public var displayName: String {
        switch self {
        case .go: "gopls"
        case .typeScript: "TypeScript server"
        }
    }

    /// The server for a path, by extension; nil for anything else.
    public init?(path: String) {
        switch (path as NSString).pathExtension.lowercased() {
        case "go": self = .go
        case "ts", "mts", "cts", "tsx", "js", "jsx", "mjs", "cjs": self = .typeScript
        default: return nil
        }
    }

    /// The `languageId` sent with `didOpen`.
    func languageID(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "go": "go"
        case "tsx": "typescriptreact"
        case "jsx": "javascriptreact"
        case "js", "mjs", "cjs": "javascript"
        default: "typescript"
        }
    }
}
