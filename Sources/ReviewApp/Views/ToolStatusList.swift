import ReviewKit
import SwiftUI

/// Each tool, where it was found, and how to install it if it was not.
struct ToolStatusList: View {
    let statuses: [ToolStatus]
    let recheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ForEach(statuses) { status in
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
                    Image(systemName: status.isUsable ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(status.isUsable ? .green : (status.tool.isRequired ? .red : .secondary))
                        .accessibilityLabel(status.isUsable ? "Available" : "Unavailable")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.tool.executableName)
                            .font(Theme.Fonts.rowTitle)
                        Text(detail(for: status))
                            .font(Theme.Fonts.meta)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            Divider()
            Button("Check Again", action: recheck)
        }
        .padding(Theme.gutter)
        .frame(width: Theme.toolPopoverWidth, alignment: .leading)
    }

    private func detail(for status: ToolStatus) -> String {
        if let problem = status.problem {
            problem
        } else if status.location == nil {
            "\(status.tool.purpose). Install: \(status.tool.installHint)"
        } else {
            status.version ?? status.location?.path ?? ""
        }
    }
}
