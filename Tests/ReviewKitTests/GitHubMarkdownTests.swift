import Testing
import ReviewKit

@Suite
struct GitHubMarkdownTests {
    @Test("Drops a bot's hidden metadata, even across lines")
    func botMetadata() {
        let body = "<!-- CURSOR_AUTOMATION_ID: b61c\n077 | RUN_ID: bc-7717 -->\nThis `jsonb_agg` runs over every row."
        #expect(GitHubMarkdown.removingHiddenComments(body) == "This `jsonb_agg` runs over every row.")
    }

    @Test("Drops template prompts between paragraphs and an unclosed comment at the end")
    func templates() {
        let body = "## Summary\n<!-- What does this change? -->\nFixes it.\n<!-- left open"
        #expect(GitHubMarkdown.removingHiddenComments(body) == "## Summary\n\nFixes it.")
    }

    @Test("Leaves a comment inside fenced code")
    func code() {
        let body = "```html\n<!-- kept -->\n```\n<!-- gone -->after"
        #expect(GitHubMarkdown.removingHiddenComments(body) == "```html\n<!-- kept -->\n```\nafter")
    }
}
