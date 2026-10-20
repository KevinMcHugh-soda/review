import ReviewDiff
import SwiftUI

/// `+12 −3`, or "binary". Tabular figures so a column of them aligns.
struct FileCounts: View {
    let file: FileDiff

    var body: some View {
        if file.isBinary {
            Text("binary")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: Theme.tightSpacing) {
                if file.additions > 0 {
                    Text("+\(file.additions)").foregroundStyle(.green)
                }
                if file.deletions > 0 {
                    Text("−\(file.deletions)").foregroundStyle(.red)
                }
            }
            .font(Theme.Fonts.counts)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(file.additions) added, \(file.deletions) removed")
        }
    }
}
