import Foundation
import Testing
import ReviewKit

@Suite
struct FileOrderTests {
    /// As git lists a Harmony PR: alphabetical, so `cmd` comes first.
    private let paths = [
        "cmd/server/main.go",
        "db/migrations/0042_sponsor.sql",
        "db/queries.sql",
        "pkg/admin/handler.go",
        "pkg/shared/time.go",
        "pkg/sponsor/handler.go",
        "spec/openapi.yaml",
    ]

    private func sorted(_ rules: [String]) -> [String] {
        FileOrder(rules: rules).sorted(paths) { $0 }
    }

    @Test("Puts listed directories first, in order, and the rest after in git's order")
    func listedFirst() {
        #expect(sorted(["db", "pkg/sponsor", "pkg/admin"]) == [
            "db/migrations/0042_sponsor.sql",
            "db/queries.sql",
            "pkg/sponsor/handler.go",
            "pkg/admin/handler.go",
            "cmd/server/main.go",
            "pkg/shared/time.go",
            "spec/openapi.yaml",
        ])
    }

    @Test("Puts unlisted files where the everything-else marker is")
    func everythingElse() {
        #expect(sorted(["db", "*", "cmd"]) == [
            "db/migrations/0042_sponsor.sql",
            "db/queries.sql",
            "pkg/admin/handler.go",
            "pkg/shared/time.go",
            "pkg/sponsor/handler.go",
            "spec/openapi.yaml",
            "cmd/server/main.go",
        ])
    }

    @Test("Files a path under the most specific directory that holds it")
    func mostSpecific() {
        let order = FileOrder(rules: ["pkg", "pkg/sponsor"])
        #expect(order.rank(of: "pkg/sponsor/handler.go") == 1)
        #expect(order.rank(of: "pkg/admin/handler.go") == 0)
    }

    @Test("Matches whole path components, not string prefixes")
    func wholeComponents() {
        let order = FileOrder(rules: ["db"])
        #expect(order.rank(of: "db/queries.sql") == 0)
        #expect(order.rank(of: "dbtools/main.go") == 1)
        #expect(order.rank(of: "db") == 0)
    }

    @Test("Tidies rules: slashes, ./, blanks and repeats")
    func normalizes() {
        #expect(FileOrder(rules: [" ./db/ ", "", "pkg/sponsor/", "db"]).rules == ["db", "pkg/sponsor"])
    }

    @Test("Moves a directory to the front, or after everything else")
    func putting() {
        let order = FileOrder(rules: ["db", "pkg/sponsor"])
        #expect(order.putting(first: "pkg/sponsor").rules == ["pkg/sponsor", "db", "*"])
        #expect(order.putting(last: "cmd/").rules == ["db", "pkg/sponsor", "*", "cmd"])
        #expect(FileOrder().putting(last: "cmd").rules == ["*", "cmd"])
    }

    @Test("Saves and loads orders by repository, ignoring case")
    func store() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-fo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileOrderStore(root: root)
        #expect(store.order(for: "sodahealth/harmony").isEmpty)
        try store.save(["sodahealth/harmony": FileOrder(rules: ["db", "*", "cmd"]), "sodahealth/nexus": FileOrder()])
        #expect(store.order(for: "SodaHealth/Harmony").rules == ["db", "*", "cmd"])
        #expect(store.load().count == 1)
    }
}
