import Foundation

/// What a `claude -p` turn reports as it goes, reduced to what the UI shows.
public enum ClaudeEvent: Hashable, Sendable {
    /// The session exists; its id is what `--resume` takes.
    case started(sessionID: String, tools: [String])
    /// More of the answer, as it is written.
    case text(String)
    /// A new assistant message began — after a tool call, say. Text that
    /// follows is a fresh paragraph.
    case messageBoundary
    /// Claude is using a tool: "Read pkg/ledger/api.go", "Grep NoDuplicateArgs".
    case activity(String)
    case finished(ClaudeResult)
}

public struct ClaudeResult: Hashable, Sendable {
    /// The final answer, which supersedes the streamed text: it leaves out the
    /// "let me look at…" narration between tool calls.
    public let text: String
    public let sessionID: String
    /// Claude Code's `total_cost_usd`: what the turn would cost at API prices.
    /// Reported on every turn, including on a subscription, where it is an
    /// estimate rather than a charge — see `isBilledToAPIKey`.
    public let costUSD: Double?
    /// The session used an API key, so `costUSD` was actually charged. False
    /// for a Claude subscription login (`apiKeySource: "none"`), whose usage
    /// counts against the plan instead.
    public var isBilledToAPIKey = false
    public let isError: Bool
    /// Tool uses the permission layer refused — a read outside the
    /// directories, for instance.
    public let deniedTools: [String]
}
