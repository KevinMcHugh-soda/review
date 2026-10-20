import SwiftUI

/// Claude's answers, rendered: fenced code blocks as code, headings bold,
/// and everything else through SwiftUI's inline Markdown, which handles
/// emphasis, `code` and links but not blocks.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ForEach(Array(Self.blocks(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
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
                case .heading(let text):
                    Text(Self.inline(text))
                        .font(Theme.Fonts.rowTitle)
                        .textSelection(.enabled)
                case .paragraph(let text):
                    Text(Self.inline(text))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    enum Block: Equatable {
        case paragraph(String)
        case heading(String)
        case code(String)
    }

    static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph = []
        }

        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else if line.hasPrefix("#") {
                flushParagraph()
                blocks.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
        }
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }

    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
