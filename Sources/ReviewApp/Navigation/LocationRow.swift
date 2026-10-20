import ReviewKit
import SwiftUI

/// One result: its line number and the code on that line. Click to go there.
struct LocationRow: View {
    let item: LocationItem
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
                Text("\(item.location.line)")
                    .font(Theme.Fonts.counts)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Theme.resultLineNumberWidth, alignment: .trailing)
                Text(item.snippet)
                    .font(Theme.Fonts.codeSmall)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Line \(item.location.line): \(item.snippet)")
    }
}
