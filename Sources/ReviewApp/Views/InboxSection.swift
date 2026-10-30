import ReviewCore
import SwiftUI

/// One of the sidebar's fetched sections — Waiting on You, or Your Pull
/// Requests — with what to say when it is empty.
struct InboxSection<Empty: View>: View {
    let title: String
    let items: [InboxItem]
    @ViewBuilder let empty: Empty
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            ForEach(items) { item in
                InboxRow(item: item)
                    .tag(SidebarItem.pullRequest(item.reference))
                    .contextMenu {
                        Link("Open on GitHub", destination: item.reference.webURL)
                    }
            }
            if items.isEmpty, !model.isLoadingInbox {
                empty
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(items.isEmpty ? title : "\(title) · \(items.count)")
        }
    }
}
