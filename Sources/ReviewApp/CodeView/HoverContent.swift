import AppKit
import SwiftUI

/// What a hover popover shows: the language server's Markdown, sized to fit
/// up to a readable width.
enum HoverContent {
    @MainActor
    static func controller(markdown: String) -> NSViewController {
        let host = NSHostingController(rootView: HoverView(markdown: markdown))
        host.sizingOptions = [.preferredContentSize]
        return host
    }
}

private struct HoverView: View {
    let markdown: String

    var body: some View {
        ScrollView {
            MarkdownText(markdown: markdown)
                .frame(maxWidth: Theme.hoverMaxWidth, alignment: .leading)
                .padding(Theme.gutter)
        }
        .frame(maxHeight: Theme.hoverMaxHeight)
        .fixedSize(horizontal: true, vertical: true)
    }
}
