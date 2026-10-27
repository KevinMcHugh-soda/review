import ReviewKit
import Testing

@Suite
struct MarkdownBlocksTests {
    @Test("Bullets, numbers and tasks become lists, with nesting and continuation lines")
    func lists() {
        let markdown = """
            - **Test members only.** The override is refused
            for a real member.
              - nested
            - [x] done

            3. three
            4. four
            """
        #expect(
            GitHubMarkdown.blocks(markdown) == [
                .list([
                    MarkdownListItem(
                        marker: .bullet,
                        blocks: [
                            .paragraph("**Test members only.** The override is refused\nfor a real member."),
                            .list([MarkdownListItem(marker: .bullet, blocks: [.paragraph("nested")])]),
                        ]
                    ),
                    MarkdownListItem(marker: .task(isDone: true), blocks: [.paragraph("done")]),
                ]),
                .list([
                    MarkdownListItem(marker: .number(3), blocks: [.paragraph("three")]),
                    MarkdownListItem(marker: .number(4), blocks: [.paragraph("four")]),
                ]),
            ]
        )
    }

    @Test("A pipe table keeps its alignments and pads short rows")
    func table() {
        let markdown = """
            | | Files | Added |
            | --- | ---: | :-: |
            | **Implementation** | 3 | +76 |
            | Total | 7 |
            """
        #expect(
            GitHubMarkdown.blocks(markdown) == [
                .table(
                    MarkdownTable(
                        alignments: [.leading, .trailing, .center],
                        header: ["", "Files", "Added"],
                        rows: [["**Implementation**", "3", "+76"], ["Total", "7", ""]]
                    )
                )
            ]
        )
    }

    @Test("Details hide their Markdown body under the summary")
    func details() {
        let markdown = """
            <details>
            <summary>Implementation files (3)</summary>

            | File | Added |
            | --- | ---: |
            | `kit.sql` | +20 |

            </details>
            after
            """
        #expect(
            GitHubMarkdown.blocks(markdown) == [
                .details(
                    summary: "Implementation files (3)",
                    blocks: [
                        .table(MarkdownTable(alignments: [.leading, .trailing], header: ["File", "Added"], rows: [["`kit.sql`", "+20"]]))
                    ]
                ),
                .paragraph("after"),
            ]
        )
    }

    @Test("Reference links resolve and their definitions disappear")
    func references() {
        let markdown = "See [EXP-1200] and [the doc][doc].\n\n[EXP-1200]: https://example.com/1200\n[doc]: <https://example.com/doc>"
        #expect(
            GitHubMarkdown.blocks(markdown) == [
                .paragraph("See [EXP-1200](https://example.com/1200) and [the doc](https://example.com/doc).")
            ]
        )
    }

    @Test("Headings, setext headings, quotes and inline HTML")
    func headingsAndQuotes() {
        let markdown = "## Summary ##\nTesting\n-------\n> quoted <b>bold</b><br>next\n\n`<b>kept</b>`"
        #expect(
            GitHubMarkdown.blocks(markdown) == [
                .heading(level: 2, text: "Summary"),
                .heading(level: 2, text: "Testing"),
                .quote([.paragraph("quoted **bold**\nnext")]),
                .paragraph("`<b>kept</b>`"),
            ]
        )
    }

    @Test("Fenced code is kept verbatim, and a rule after it stays a rule")
    func codeAndRule() {
        let markdown = "```go\n- not a list\n```\n\n---\n\nDoc."
        #expect(GitHubMarkdown.blocks(markdown) == [.code("- not a list"), .rule, .paragraph("Doc.")])
    }
}
