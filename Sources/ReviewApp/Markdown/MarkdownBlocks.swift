import ReviewKit
import SwiftUI

/// A run of Markdown blocks, stacked. Lists, quotes and details nest it.
struct MarkdownBlocks: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(MarkdownText.inline(text))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .heading(let level, let text):
                    Text(MarkdownText.inline(text))
                        .font(Theme.Fonts.markdownHeading(level: level))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                case .code(let code):
                    // Unwrapped, scrolling sideways, as code should be.
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(Theme.Fonts.codeSmall)
                            .textSelection(.enabled)
                            .fixedSize()
                            .padding(Theme.spacing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Theme.codeBlockCornerRadius))
                case .rule:
                    Divider()
                case .list(let items):
                    MarkdownList(items: items)
                case .table(let table):
                    MarkdownTableView(table: table)
                case .quote(let blocks):
                    MarkdownBlocks(blocks: blocks)
                        .foregroundStyle(.secondary)
                        .padding(.leading, Theme.spacing)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.quaternary)
                                .frame(width: Theme.quoteBarWidth)
                        }
                case .details(let summary, let blocks):
                    MarkdownDetails(summary: summary, blocks: blocks)
                }
            }
        }
    }
}
