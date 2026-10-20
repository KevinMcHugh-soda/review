import Foundation

/// Zero-based line, and character offset in **UTF-16 code units** — the
/// encoding this client negotiates, and the one `NSString` indexes in.
public struct Position: Codable, Hashable, Sendable {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

/// LSP's `Range`, renamed so it never shadows `Swift.Range` in importers.
public struct TextRange: Codable, Hashable, Sendable {
    public let start: Position
    public let end: Position

    public init(start: Position, end: Position) {
        self.start = start
        self.end = end
    }
}

public struct Location: Codable, Hashable, Sendable {
    public let uri: String
    public let range: TextRange

    public init(uri: String, range: TextRange) {
        self.uri = uri
        self.range = range
    }

    /// The file this location is in, when its URI is a `file:` URL — which
    /// every location gopls and tsserver return for source files is.
    public var fileURL: URL? {
        URL(string: uri).flatMap { $0.isFileURL ? $0 : nil }
    }
}

/// `textDocument/definition` may answer with links instead of locations.
struct LocationLink: Codable, Hashable, Sendable {
    let targetUri: String
    let targetRange: TextRange
    let targetSelectionRange: TextRange
}

/// One node in a call hierarchy. `data` is the server's own bookkeeping and
/// must go back verbatim with `callHierarchy/incomingCalls`, which is why the
/// item keeps the raw JSON it arrived as.
public struct CallHierarchyItem: Hashable, Sendable {
    public let name: String
    public let detail: String?
    /// LSP's `SymbolKind` number: 6 method, 12 function, …
    public let kind: Int
    public let location: Location
    let raw: JSONValue

    init(raw: JSONValue) throws {
        struct Fields: Decodable {
            let name: String
            let detail: String?
            let kind: Int
            let uri: String
            let selectionRange: TextRange
        }
        let fields = try raw.decode(as: Fields.self)
        name = fields.name
        detail = fields.detail
        kind = fields.kind
        location = Location(uri: fields.uri, range: fields.selectionRange)
        self.raw = raw
    }
}

/// A caller, and where in it the calls are.
public struct IncomingCall: Hashable, Sendable {
    public let caller: CallHierarchyItem
    /// The call sites, in the caller's file.
    public let ranges: [TextRange]
}

/// `textDocument/hover` reduced to text: servers send Markdown, a plain
/// string, or a list of marked strings.
public struct Hover: Hashable, Sendable {
    public let markdown: String
}
