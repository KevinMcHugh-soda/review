import Testing
import ReviewCore

@Suite
struct PullRequestReferenceTests {
    private let expected = PullRequestReference(owner: "acme", repository: "widgets", number: 14683)

    @Test("Accepts the forms a reviewer pastes", arguments: [
        "https://github.com/acme/widgets/pull/14683",
        "https://github.com/acme/widgets/pull/14683/files",
        "https://github.com/acme/widgets/pull/14683/files#diff-abc123",
        "https://github.com/acme/widgets/pull/14683?w=1",
        "github.com/acme/widgets/pull/14683",
        "  https://www.github.com/acme/widgets/pull/14683\n",
        "acme/widgets#14683",
    ])
    func acceptsTheFormsAReviewerPastes(input: String) throws {
        #expect(try PullRequestReference(parsing: input) == expected)
    }

    @Test("Rejects anything that does not name a pull request", arguments: [
        "",
        "https://github.com/acme/widgets",
        "https://github.com/acme/widgets/issues/14683",
        "https://gitlab.com/acme/widgets/pull/14683",
        "https://github.com/acme/widgets/pull/0",
        "https://github.com/acme/widgets/pull/abc",
        "acme/widgets#",
        "acme#14683",
        "ac me/widgets#14683",
    ])
    func rejectsAnythingThatDoesNotNameAPullRequest(input: String) {
        #expect(throws: PullRequestReference.ParseError.self) {
            try PullRequestReference(parsing: input)
        }
    }

    @Test("Describes itself in gh's shorthand")
    func describesItselfInGhsShorthand() {
        #expect(expected.description == "acme/widgets#14683")
        #expect(expected.webURL.absoluteString == "https://github.com/acme/widgets/pull/14683")
    }
}
