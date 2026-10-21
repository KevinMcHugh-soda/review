import Foundation

/// Cleaning up Markdown written for GitHub before it is rendered here.
public enum GitHubMarkdown {
    /// Drops `<!-- … -->` comments, which GitHub hides: PR templates' prompts,
    /// and the IDs bots like Cursor leave in their comments. An unclosed
    /// comment hides the rest, as on GitHub. Fenced code is left alone.
    public static func removingHiddenComments(_ markdown: String) -> String {
        guard markdown.contains("<!--") else { return markdown }
        var output: [String] = []
        var prose: [String] = []
        var isInCode = false

        func flushProse() {
            guard !prose.isEmpty else { return }
            output.append(stripComments(prose.joined(separator: "\n")))
            prose = []
        }

        for line in markdown.components(separatedBy: "\n") {
            let isFence = line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            if isInCode {
                output.append(line)
                if isFence { isInCode = false }
            } else if isFence {
                flushProse()
                output.append(line)
                isInCode = true
            } else {
                prose.append(line)
            }
        }
        flushProse()
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripComments(_ text: String) -> String {
        var result = ""
        var rest = text[...]
        while let open = rest.range(of: "<!--") {
            result += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "-->") else { return result }
            rest = rest[close.upperBound...]
        }
        return result + rest
    }
}
