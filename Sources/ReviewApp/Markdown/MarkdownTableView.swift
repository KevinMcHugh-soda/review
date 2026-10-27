import ReviewKit
import SwiftUI

/// A pipe table as a grid: a bold header over a hairline, each column
/// aligned as its delimiter row says. Cells wrap rather than scroll, since
/// the inspector is narrow.
struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.spacing, verticalSpacing: Theme.tightSpacing) {
            GridRow {
                ForEach(Array(table.header.enumerated()), id: \.offset) { column, text in
                    cell(text)
                        .fontWeight(.semibold)
                        .gridColumnAlignment(alignment(of: column))
                }
            }
            Divider()
                .gridCellUnsizedAxes(.horizontal)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, text in
                        cell(text)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private func cell(_ text: String) -> some View {
        Text(MarkdownText.inline(text))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func alignment(of column: Int) -> HorizontalAlignment {
        guard column < table.alignments.count else { return .leading }
        return switch table.alignments[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
