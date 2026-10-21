import ReviewCore
import SwiftUI

/// A status group's header in the sidebar. Merged and Closed offer to close
/// every PR in them at once.
struct GroupHeader: View {
    let status: PullRequestStatus
    let count: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Text("\(status.title) · \(count)")
            Spacer()
            if status.isFinished {
                Button("Close All") { model.closeAll(status) }
                    .buttonStyle(.borderless)
                    .font(Theme.Fonts.meta)
                    .help("Close every \(status.title.lowercased()) pull request")
            }
        }
    }
}
