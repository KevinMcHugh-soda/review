import Foundation
import Testing
@testable import ReviewLSP

@Suite
struct FramingTests {
    @Test("Reassembles a message split across reads")
    func splitMessage() throws {
        let frame = try MessageFraming.encode(["id": 1, "result": "ok"])
        var decoder = FrameDecoder()
        var messages: [Data] = []
        for byte in frame {
            messages += try decoder.append(Data([byte]))
        }
        #expect(messages.count == 1)
        #expect(try JSONDecoder().decode(JSONValue.self, from: messages[0])["result"] == "ok")
    }

    @Test("Separates several messages delivered in one read")
    func mergedMessages() throws {
        let frames = try [1, 2, 3].map { try MessageFraming.encode(["id": .number(Double($0))]) }
        var decoder = FrameDecoder()
        let messages = try decoder.append(frames.reduce(Data(), +))
        #expect(try messages.map { try JSONDecoder().decode(JSONValue.self, from: $0)["id"]?.intValue } == [1, 2, 3])
    }

    /// Content-Length counts bytes, not characters.
    @Test("Counts multi-byte characters in bytes")
    func multibyte() throws {
        let frame = try MessageFraming.encode(["text": "héllo 🙂"])
        var decoder = FrameDecoder()
        let messages = try decoder.append(frame)
        #expect(try JSONDecoder().decode(JSONValue.self, from: messages[0])["text"] == "héllo 🙂")
    }

    @Test("Accepts a Content-Type header and any header casing")
    func headers() throws {
        let body = Data(#"{"id":7}"#.utf8)
        let frame = Data("content-length: \(body.count)\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n".utf8) + body
        var decoder = FrameDecoder()
        #expect(try decoder.append(frame).count == 1)
    }

    @Test("Writes whole numbers as integers")
    func integers() throws {
        let data = try JSONEncoder().encode(JSONValue.object(["id": 3, "x": .number(1.5)]))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""id":3"#))
        #expect(text.contains(#""x":1.5"#))
    }

    @Test("Round-trips booleans as booleans, not numbers")
    func booleans() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":true,"b":1,"c":0}"#.utf8))
        #expect(value["a"] == .bool(true))
        #expect(value["b"] == .number(1))
        #expect(value["c"] == .number(0))
    }

    @Test("Reads definition results as locations, location lists or links")
    func definitionShapes() throws {
        let range: JSONValue = ["start": ["line": 1, "character": 2], "end": ["line": 1, "character": 5]]
        let location: JSONValue = ["uri": "file:///a.go", "range": range]
        let link: JSONValue = ["targetUri": "file:///b.go", "targetRange": range, "targetSelectionRange": range]
        #expect(try LanguageServer.decodeLocations(.null, method: "m").isEmpty)
        #expect(try LanguageServer.decodeLocations(location, method: "m").map(\.uri) == ["file:///a.go"])
        #expect(try LanguageServer.decodeLocations([location, link], method: "m").map(\.uri) == ["file:///a.go", "file:///b.go"])
    }

    @Test("Reads hover contents in every shape servers send")
    func hoverShapes() {
        #expect(LanguageServer.decodeHover(["contents": ["kind": "markdown", "value": "**x**"]])?.markdown == "**x**")
        #expect(LanguageServer.decodeHover(["contents": "plain"])?.markdown == "plain")
        #expect(LanguageServer.decodeHover(["contents": [["language": "go", "value": "func f()"], "doc"]])?.markdown == "```go\nfunc f()\n```\n\ndoc")
        #expect(LanguageServer.decodeHover(.null) == nil)
    }
}
