import ReviewCore
import SwiftUI

/// Every notification the app has raised, newest first: review requests,
/// assignments, replies, comments and Claude's answers. Clicking one opens
/// what it is about.
struct NotificationsPanel: View {
    @Environment(AppModel.self) private var model

    private var records: [NotificationRecord] {
        model.notificationLog.records
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if records.isEmpty {
                EmptyState(
                    "No Notifications",
                    systemImage: "bell",
                    description: "Review requests, replies, comments and Claude's answers appear here."
                )
            } else {
                List {
                    ForEach(records) { record in
                        NotificationListItem(record: record) {
                            model.isNotificationsShown = false
                            model.open(record)
                        } setRead: { isRead in
                            model.setRead(isRead, id: record.id)
                        }
                        .contextMenu { menu(for: record) }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: Theme.notificationsWidth, height: Theme.notificationsHeight)
    }

    private var header: some View {
        HStack(spacing: Theme.tightSpacing) {
            Text("Notifications")
                .font(Theme.Fonts.panelTitle)
            Spacer()
            Button("Mark All as Read") { model.markAllNotificationsRead() }
                .disabled(model.notificationLog.unreadCount == 0)
            Button("Clear", role: .destructive) { model.removeAllNotifications() }
                .disabled(records.isEmpty)
        }
        .buttonStyle(.link)
        .font(Theme.Fonts.meta)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.spacing)
    }

    @ViewBuilder
    private func menu(for record: NotificationRecord) -> some View {
        Button(record.isRead ? "Mark as Unread" : "Mark as Read") {
            model.setRead(!record.isRead, id: record.id)
        }
        Link("Open on GitHub", destination: record.reference.webURL)
        CopyLinkButton(url: record.reference.webURL)
        Divider()
        Button("Delete", role: .destructive) { model.removeNotification(id: record.id) }
    }
}
