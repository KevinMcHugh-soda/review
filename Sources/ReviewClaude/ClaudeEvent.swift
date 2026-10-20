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
    public let costUSD: Double?
    public let isError: Bool
    /// Tool uses the permission layer refused — a read outside the
    /// directories, for instance.
    public let deniedTools: [String]
}
