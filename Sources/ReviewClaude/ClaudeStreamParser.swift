import Foundation

/// Turns `--output-format stream-json --verbose --include-partial-messages`
/// lines into `ClaudeEvent`s.
///
/// The format, as observed from Claude Code 2.1.304: a `system/init` line;
/// `stream_event` lines wrapping the Messages API's streaming events
/// (`content_block_delta` with a `text_delta` carries answer text);
/// `assistant` lines with each complete message, whose `tool_use` blocks say
/// what Claude is reading; `user` lines with tool results; one `result` line.
/// Unknown lines are skipped, so new event types do not break a turn.
public struct ClaudeStreamParser {
    private var buffer = Data()
    /// From the init line: where the session's credentials came from.
    private var apiKeySource: String?

    public init() {}

    /// Adds a chunk of stdout and returns the events from every line it
    /// completed.
    public mutating func append(_ chunk: Data) -> [ClaudeEvent] {
        buffer.append(chunk)
        var events: [ClaudeEvent] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer = Data(buffer[buffer.index(after: newline)...])
            for event in Self.events(fromLine: line) {
                switch event {
                case .started:
                    apiKeySource = Self.apiKeySource(inLine: line)
                    events.append(event)
                case .finished(var result):
                    // "none" is a Claude subscription login; any other source
                    // — ANTHROPIC_API_KEY, an apiKeyHelper — is billed.
                    result.isBilledToAPIKey = apiKeySource.map { $0 != "none" } ?? false
                    events.append(.finished(result))
                case .text, .messageBoundary, .activity:
                    events.append(event)
                }
            }
        }
        return events
    }

    static func apiKeySource(inLine line: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: line) as? [String: Any])?["apiKeySource"] as? String
    }

    static func events(fromLine line: Data) -> [ClaudeEvent] {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String
        else { return [] }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init", let session = object["session_id"] as? String else { return [] }
            return [.started(sessionID: session, tools: object["tools"] as? [String] ?? [])]

        case "stream_event":
            guard let event = object["event"] as? [String: Any], let eventType = event["type"] as? String else { return [] }
            switch eventType {
            case "message_start":
                return [.messageBoundary]
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String
                else { return [] }
                return [.text(text)]
            default:
                return []
            }

        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { return [] }
            return content.compactMap { block in
                guard block["type"] as? String == "tool_use", let name = block["name"] as? String else { return nil }
                return .activity(describe(tool: name, input: block["input"] as? [String: Any] ?? [:]))
            }

        case "result":
            let denied = (object["permission_denials"] as? [[String: Any]] ?? []).compactMap { $0["tool_name"] as? String }
            return [.finished(ClaudeResult(
                text: object["result"] as? String ?? "",
                sessionID: object["session_id"] as? String ?? "",
                costUSD: object["total_cost_usd"] as? Double,
                isError: object["is_error"] as? Bool ?? (object["subtype"] as? String != "success"),
                deniedTools: denied
            ))]

        default:
            return []
        }
    }

    /// "Read args.go", "Grep NoDuplicateArgs", "Glob **/*_test.go".
    static func describe(tool: String, input: [String: Any]) -> String {
        let detail: String? =
            switch tool {
            case "Read": (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
            case "Grep": input["pattern"] as? String
            case "Glob": input["pattern"] as? String
            default: nil
            }
        return detail.map { "\(tool) \($0)" } ?? tool
    }
}
