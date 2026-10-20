import ReviewKit
import SwiftUI

/// One line at the foot of the sidebar: are the tools there? Click for the
/// detail `review doctor` prints.
struct ToolStatusFooter: View {
    @Environment(AppModel.self) private var model
    @State private var isShowingDetail = false

    var body: some View {
        Button {
            isShowingDetail.toggle()
        } label: {
            Label(summary, systemImage: symbol)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.spacing)
        .background(.bar)
        .popover(isPresented: $isShowingDetail, arrowEdge: .top) {
            ToolStatusList(statuses: model.toolStatuses) {
                Task { await model.checkTools() }
            }
        }
    }

    private var summary: String {
        if model.isCheckingTools || model.toolStatuses.isEmpty {
            "Checking tools…"
        } else if let missing = model.missingRequiredTools.first {
            "\(missing.tool.executableName) unavailable"
        } else {
            "\(model.toolStatuses.count(where: \.isUsable)) of \(model.toolStatuses.count) tools ready"
        }
    }

    private var symbol: String {
        if model.isCheckingTools || model.toolStatuses.isEmpty {
            "hourglass"
        } else if model.missingRequiredTools.isEmpty {
            "checkmark.circle"
        } else {
            "exclamationmark.triangle"
        }
    }
}
