import Foundation
import ReviewCore
import ReviewDiff
import Testing
@testable import ReviewKit

@Suite
struct DailyDriverTests {
    private func file(newBlob: String?, oldBlob: String? = "a1", path: String = "x.go", deleted: Bool = false) -> FileDiff {
        FileDiff(oldPath: path, newPath: deleted ? nil : path, oldBlob: oldBlob, newBlob: newBlob, hunks: [])
    }

    @Test("Keeps a file viewed across a push that does not change it, and unmarks it when one does")
    func viewedFollowsContent() {
        var notes = ReviewNotes()
        let before = file(newBlob: "b1")
        notes.setViewed(true, before, headSHA: "head-1")
        #expect(notes.isViewed(before, headSHA: "head-1"))
        // Another file changed; this one's blob is the same at the new head.
        #expect(notes.isViewed(file(newBlob: "b1"), headSHA: "head-2"))
        // This file changed.
        #expect(!notes.isViewed(file(newBlob: "b2"), headSHA: "head-2"))
        notes.setViewed(false, before, headSHA: "head-1")
        #expect(!notes.isViewed(before, headSHA: "head-1"))
    }

    @Test("Pins a pure rename, which has no blob ids, to the head commit")
    func renameFallsBackToCommit() {
        var notes = ReviewNotes()
        let rename = FileDiff(oldPath: "a.go", newPath: "b.go", hunks: [])
        notes.setViewed(true, rename, headSHA: "head-1")
        #expect(notes.isViewed(rename, headSHA: "head-1"))
        #expect(!notes.isViewed(rename, headSHA: "head-2"))
    }

    @Test("Pins a deleted file to its old blob")
    func deletedFile() {
        #expect(file(newBlob: nil, oldBlob: "gone", deleted: true).viewedKey(headSHA: "h") == "deleted:gone")
    }

    @Test("Loads notes saved before viewed files existed")
    func oldNotesStillLoad() throws {
        let json = #"{"drafts":[],"overview":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(ReviewNotes.self, from: Data(json.utf8)).viewed.isEmpty)
    }

    @Test("Remembers which pull requests are open, in order")
    func workspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-ws-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(root: root)
        #expect(store.load().isEmpty)
        let references = [
            PullRequestReference(owner: "sindresorhus", repository: "ky", number: 881),
            PullRequestReference(owner: "spf13", repository: "cobra", number: 2397),
        ]
        try store.save(references)
        #expect(store.load() == references)
    }

    @Test("Remembers tracked repositories, dropping a name it cannot read")
    func trackedRepositories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-tr-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TrackedRepositoriesStore(root: root)
        #expect(store.load().isEmpty)
        let repositories = [RepositoryName(owner: "sodahealth", name: "harmony"), RepositoryName(owner: "sodahealth", name: "nexus")]
        try store.save(repositories)
        #expect(store.load() == repositories)
        try Data(#"["sodahealth/harmony", "not a repo"]"#.utf8).write(to: store.file)
        #expect(store.load() == [repositories[0]])
    }

    @Test("Remembers the browser's scope and filter, and starts from defaults")
    func browse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-br-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowseStore(root: root)
        #expect(store.load() == BrowseStore.Saved())
        let saved = BrowseStore.Saved(
            scope: .repository(RepositoryName(owner: "sodahealth", name: "harmony")),
            filter: PullRequestFilter(readiness: .draft, people: [PersonCondition(role: .author, login: "@me", isExcluded: true)])
        )
        try store.save(saved)
        #expect(store.load() == saved)
        try Data("not json".utf8).write(to: store.file)
        #expect(store.load() == BrowseStore.Saved())
    }
}
