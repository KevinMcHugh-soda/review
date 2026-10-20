import Foundation
import ReviewCore

/// Drafts on disk: one JSON file per pull request, written atomically.
///
/// A review has tens of drafts, so a database would buy nothing but a
/// dependency. Sorted keys keep the file diffable for anyone who looks.
public struct NotesStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func file(for reference: PullRequestReference) -> URL {
        root.appendingPathComponent("reviews", isDirectory: true)
            .appendingPathComponent(reference.owner, isDirectory: true)
            .appendingPathComponent(reference.repository, isDirectory: true)
            .appendingPathComponent("\(reference.number).json")
    }

    /// Empty notes when none have been saved yet.
    public func load(_ reference: PullRequestReference) throws -> ReviewNotes {
        let url = file(for: reference)
        guard FileManager.default.fileExists(atPath: url.path) else { return ReviewNotes() }
        return try Self.decoder.decode(ReviewNotes.self, from: Data(contentsOf: url))
    }

    public func save(_ notes: ReviewNotes, for reference: PullRequestReference) throws {
        let url = file(for: reference)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(notes).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
