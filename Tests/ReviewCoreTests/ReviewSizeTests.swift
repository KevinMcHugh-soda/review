import Foundation
import ReviewCore
import Testing

@Suite
struct ReviewSizeTests {
    /// Lines from harmony's own `.gitattributes`.
    private let harmony = GitAttributes(parsing: """
        **/languages/catalog.go linguist-generated=true
        pkg/microportal/static/dynamsoft/* linguist-vendored
        # templ (make <service>-templates)
        **/*_templ.go linguist-generated=true
        internal/*api/types.go linguist-generated=true
        external/**/client.go linguist-generated=true
        external/e6/*.go -linguist-generated
        internal/*/db/*.sql.go linguist-generated=true
        sdks/** linguist-generated=true
        pkg/iowaeac/testdata/** -text
        """)

    @Test("Matches anchored patterns, wildcards within a component, and ** across them")
    func patterns() {
        #expect(harmony.isGenerated("internal/adminapi/types.go"))
        #expect(!harmony.isGenerated("internal/adminapi/v2/types.go"))
        #expect(harmony.isGenerated("internal/ledger/db/funding.sql.go"))
        #expect(harmony.isGenerated("pkg/microportal/languages/catalog.go"))
        #expect(harmony.isGenerated("languages/catalog.go"))
        #expect(harmony.isGenerated("sdks/ts/src/index.ts"))
        #expect(!harmony.isGenerated("sdks"))
        #expect(harmony.isGenerated("pkg/hub/views/page_templ.go"))
        #expect(!harmony.isGenerated("pkg/hub/views/page.templ"))
    }

    @Test("A later line wins, and vendored counts as generated")
    func lastLineWins() {
        #expect(harmony.isGenerated("external/kroger/client.go"))
        #expect(!harmony.isGenerated("external/e6/client.go"))
        #expect(harmony.isGenerated("pkg/microportal/static/dynamsoft/dbr.js"))
        #expect(!harmony.isGenerated("pkg/microportal/static/dynamsoft/sub/dbr.js"))
        #expect(harmony.value(of: "text", for: "pkg/iowaeac/testdata/a.txt") == .unset)
    }

    @Test("Values, unspecifying, comments and directory-only patterns")
    func syntax() {
        let attributes = GitAttributes(parsing: """
            *.pb.go linguist-generated
            gen/** linguist-generated=false
            keep.pb.go !linguist-generated
            build/ linguist-generated
            # *.go linguist-generated
            /root.go linguist-generated eol=lf
            """)
        #expect(attributes.isGenerated("api/v1/thing.pb.go"))
        #expect(!attributes.isGenerated("gen/thing.go"))
        #expect(!attributes.isGenerated("keep.pb.go"))
        #expect(!attributes.isGenerated("build/out.js"))
        #expect(!attributes.isGenerated("main.go"))
        #expect(attributes.isGenerated("root.go"))
        #expect(!attributes.isGenerated("pkg/root.go"))
        #expect(attributes.value(of: "eol", for: "root.go") == .string("lf"))
    }

    @Test("Generated wins, then tests, then documentation, then implementation")
    func categories() {
        let cases: [(String, ReviewSize.Category)] = [
            ("sdks/README.md", .generated),
            ("pkg/ledger/api_test.go", .tests),
            ("scripts/pr-line-count_test.sh", .tests),
            ("web/app/src/thing.spec.tsx", .tests),
            ("pkg/iowaeac/testdata/notes.md", .tests),
            ("test/functional/main.go", .tests),
            ("README.md", .documentation),
            ("pkg/ledger/docs/flow.txt", .documentation),
            ("decisions/0001-use-go.txt", .documentation),
            ("pkg/decisions/rules.go", .implementation),
            (".cursor/rules/go.mdc", .documentation),
            ("pkg/test.go", .implementation),
            ("pkg/ledger/api.go", .implementation),
        ]
        for (path, category) in cases {
            #expect(ReviewSize.category(of: path, attributes: harmony) == category, "\(path)")
        }
    }

    @Test("Tallies each category and the total")
    func tallies() {
        let size = ReviewSize(
            files: [
                ChangedFileCount(path: "pkg/ledger/api.go", additions: 10, deletions: 2),
                ChangedFileCount(path: "pkg/ledger/handler.go", additions: 5, deletions: 0),
                ChangedFileCount(path: "internal/ledgerapi/types.go", additions: 900, deletions: 40),
                ChangedFileCount(path: "pkg/ledger/api_test.go", additions: 30, deletions: 1),
            ],
            attributes: harmony
        )
        #expect(size[.implementation] == ReviewSize.Tally(files: 2, additions: 15, deletions: 2))
        #expect(size[.generated] == ReviewSize.Tally(files: 1, additions: 900, deletions: 40))
        #expect(size[.documentation] == ReviewSize.Tally())
        #expect(size.total == ReviewSize.Tally(files: 4, additions: 945, deletions: 43))
    }
}
