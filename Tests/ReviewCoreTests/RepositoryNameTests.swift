import Foundation
import ReviewCore
import Testing

@Suite
struct RepositoryNameTests {
    private let harmony = RepositoryName(owner: "sodahealth", name: "harmony")

    @Test("Parses owner/repo and repository URLs, with or without a scheme")
    func parses() throws {
        #expect(try RepositoryName(parsing: "sodahealth/harmony") == harmony)
        #expect(try RepositoryName(parsing: "  sodahealth/harmony\n") == harmony)
        #expect(try RepositoryName(parsing: "https://github.com/sodahealth/harmony") == harmony)
        #expect(try RepositoryName(parsing: "github.com/sodahealth/harmony/pull/12/files") == harmony)
    }

    @Test("Rejects a bare name, a deeper path that is not a URL, and other hosts")
    func rejects() {
        for input in ["harmony", "a/b/c", "https://gitlab.com/sodahealth/harmony", "sodahealth/har mony", ""] {
            #expect(throws: RepositoryName.ParseError.self) { try RepositoryName(parsing: input) }
        }
    }

    @Test("Encodes as owner/repo")
    func codable() throws {
        let data = try JSONEncoder().encode([harmony])
        #expect(String(decoding: data, as: UTF8.self) == #"["sodahealth\/harmony"]"#)
        #expect(try JSONDecoder().decode([RepositoryName].self, from: data) == [harmony])
    }

    @Test("Merges an item found by several searches into one with every reason")
    func mergesReasons() {
        let reference = PullRequestReference(owner: "acme", repository: "r", number: 1)
        let other = PullRequestReference(owner: "acme", repository: "r", number: 2)
        let date = Date(timeIntervalSince1970: 1_000)
        let items = [
            InboxItem(reference: reference, title: "One", author: "a", isDraft: false, updatedAt: date, reasons: [.reviewRequested]),
            InboxItem(reference: other, title: "Two", author: "me", isDraft: false, updatedAt: date + 10, reasons: [.authored]),
            InboxItem(reference: reference, title: "One", author: "a", isDraft: false, updatedAt: date, reasons: [.assigned]),
        ]
        let merged = items.mergingReasons()
        #expect(merged.map(\.reference) == [other, reference])
        #expect(merged[1].reasons == [.reviewRequested, .assigned])
        #expect(merged[0].isAuthored)
    }
}
