import Foundation

/// A Claude turn in flight: what it has said so far and what it is doing.
struct AskProgress: Equatable {
    var text = ""
    /// "Read args.go" — the latest tool use, while Claude is looking.
    var activity: String?
}

/// The overview conversation's key wherever drafts are keyed by id.
let overviewID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
