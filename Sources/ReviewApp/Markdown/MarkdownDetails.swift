import ReviewKit
import SwiftUI

/// `<details>`: closed until opened, as on GitHub.
struct MarkdownDetails: View {
    let summary: String
    let blocks: [MarkdownBlock]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            MarkdownBlocks(blocks: blocks)
                .padding(.top, Theme.tightSpacing)
        } label: {
            Text(MarkdownText.inline(summary))
        }
    }
}
