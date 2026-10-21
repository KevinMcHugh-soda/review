import ReviewKit
import SwiftUI

/// GitHub-flavoured Markdown, laid out natively: PR descriptions, review
/// comments, Claude's answers and hovers. `GitHubMarkdown.blocks` does the
/// block structure; SwiftUI's inline Markdown handles emphasis, `code` and
/// links within each block.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        MarkdownBlocks(blocks: GitHubMarkdown.blocks(markdown))
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
