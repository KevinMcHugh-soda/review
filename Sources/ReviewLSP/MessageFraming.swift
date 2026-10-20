import Foundation

/// LSP's base protocol: `Content-Length: N\r\n\r\n` then N bytes of JSON.
enum MessageFraming {
    static func encode(_ message: JSONValue) throws -> Data {
        let body = try JSONEncoder().encode(message)
        return Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
    }
}

/// Reassembles messages from stdout chunks, which split and merge frames
/// arbitrarily — one read can hold half a header, or three whole messages.
struct FrameDecoder {
    enum DecodeError: Error, Equatable {
        case missingContentLength(String)
    }

    private var buffer = Data()
    private static let separator = Data("\r\n\r\n".utf8)

    /// Adds a chunk and returns every message it completed.
    mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var messages: [Data] = []
        while let headerEnd = buffer.range(of: Self.separator) {
            let header = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
            guard let length = Self.contentLength(header) else {
                throw DecodeError.missingContentLength(header)
            }
            let bodyStart = headerEnd.upperBound
            guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { break }
            let bodyEnd = buffer.index(bodyStart, offsetBy: length)
            messages.append(Data(buffer[bodyStart..<bodyEnd]))
            buffer = Data(buffer[bodyEnd...])
        }
        return messages
    }

    /// Header names are case-insensitive; `Content-Type` may also appear.
    private static func contentLength(_ header: String) -> Int? {
        header.split(separator: "\r\n").lazy.compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }.first
    }
}
