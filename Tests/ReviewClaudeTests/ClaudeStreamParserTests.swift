import Foundation
import Testing
@testable import ReviewClaude

/// Against output captured from Claude Code 2.1.304 (paths sanitised).
@Suite
struct ClaudeStreamParserTests {
    @Test("Reads a turn that uses a tool, then answers")
    func readThenAnswer() throws {
        let events = try events(from: "read-then-answer")

        guard case .started(let session, let tools) = events.first else {
            Issue.record("first event was \(String(describing: events.first))")
            return
        }
        #expect(!session.isEmpty)
        #expect(tools == ["Glob", "Grep", "Read"])
        #expect(events.contains(.activity("Read math.go")))

        let streamed = events.compactMap { if case .text(let text) = $0 { text } else { nil } }.joined()
        let result = try #require(events.compactMap { if case .finished(let result) = $0 { result } else { nil } }.first)
        #expect(!result.isError)
        #expect(result.sessionID == session)
        #expect((result.costUSD ?? 0) > 0)
        #expect(result.text.contains("Double"))
        // The streamed text is the answer as it was written.
        #expect(streamed.contains(result.text.prefix(20)))
        #expect(events.count { $0 == .messageBoundary } == 2)
    }

    @Test("Reports a read the permission layer refused")
    func deniedRead() throws {
        let result = try #require(try events(from: "denied-read").compactMap {
            if case .finished(let result) = $0 { result } else { nil }
        }.first)
        #expect(result.deniedTools == ["Read"])
    }

    @Test("Reassembles lines split across chunks and ignores unknown types")
    func chunking() {
        var parser = ClaudeStreamParser()
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"héllo"}}}"#
        let data = Data((#"{"type":"something_new"}"# + "\n" + line + "\n").utf8)
        var events: [ClaudeEvent] = []
        for byte in data {
            events += parser.append(Data([byte]))
        }
        #expect(events == [.text("héllo")])
    }

    @Test("Describes tool use the way the UI shows it")
    func activity() {
        #expect(ClaudeStreamParser.describe(tool: "Read", input: ["file_path": "/w/pkg/ledger/api.go"]) == "Read api.go")
        #expect(ClaudeStreamParser.describe(tool: "Grep", input: ["pattern": "NoDuplicateArgs"]) == "Grep NoDuplicateArgs")
        #expect(ClaudeStreamParser.describe(tool: "Task", input: [:]) == "Task")
    }

    @Test("Builds the safety boundary into every invocation")
    func arguments() {
        let request = ClaudeRequest(
            prompt: "why?", systemPrompt: "context",
            workingDirectory: URL(fileURLWithPath: "/scratch"),
            readableDirectories: [URL(fileURLWithPath: "/worktree")],
            resumeSessionID: "abc"
        )
        let arguments = ClaudeClient.arguments(for: request)
        #expect(arguments.contains("--restricted"))
        #expect(arguments.contains("--strict-mcp-config"))
        #expect(arguments.adjacent("--tools", "Read,Grep,Glob"))
        #expect(arguments.adjacent("--add-dir", "/worktree"))
        #expect(arguments.adjacent("--resume", "abc"))
        #expect(arguments.adjacent("-p", "why?"))
        #expect(!arguments.contains("--bare"))
        #expect(!arguments.contains { $0.contains("bypassPermissions") })
    }

    private func events(from name: String) throws -> [ClaudeEvent] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Streams"))
        var parser = ClaudeStreamParser()
        return parser.append(try Data(contentsOf: url))
    }
}

extension [String] {
    fileprivate func adjacent(_ flag: String, _ value: String) -> Bool {
        guard let index = firstIndex(of: flag), indices.contains(index + 1) else { return false }
        return self[index + 1] == value
    }
}
