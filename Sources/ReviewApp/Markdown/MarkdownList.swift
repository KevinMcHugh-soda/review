import ReviewKit
import SwiftUI

/// Bullets, numbers or checkboxes in a column, the items' text aligned
/// beside them.
struct MarkdownList: View {
    let items: [MarkdownListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Theme.tightSpacing) {
                    marker(item.marker)
                        .frame(minWidth: Theme.listMarkerWidth, alignment: .trailing)
                    MarkdownBlocks(blocks: item.blocks)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(_ marker: MarkdownListItem.Marker) -> some View {
        switch marker {
        case .bullet:
            Text(verbatim: "•")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .number(let number):
            Text(verbatim: "\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .task(let isDone):
            Image(systemName: isDone ? "checkmark.square.fill" : "square")
                .foregroundStyle(isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityLabel(isDone ? "Done" : "Not done")
        }
    }
}
