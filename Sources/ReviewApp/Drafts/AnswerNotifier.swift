import AppKit
import ReviewCore
import UserNotifications

/// Tells the reviewer Claude has answered, with a system notification.
///
/// Skipped when they are already looking at the answer: the app active, this
/// PR selected, the drafts inspector open. Otherwise — another app, another
/// PR, the inspector closed — it shows, and clicking it goes to the draft.
@MainActor
enum AnswerNotifier {
    nonisolated static let pullRequestKey = "pullRequest"
    nonisolated static let draftKey = "draft"

    /// Asked once, the first time the reviewer asks Claude anything — when a
    /// notification is about to be useful, rather than at launch.
    static func requestPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    static func notify(
        pullRequest: PullRequestReference,
        draft: UUID?,
        title: String,
        answer: String,
        isError: Bool,
        isBeingWatched: Bool
    ) {
        guard !(NSApp.isActive && isBeingWatched) else { return }
        let content = UNMutableNotificationContent()
        content.title = isError ? "Claude couldn't answer" : "Claude answered"
        content.subtitle = title
        content.body = preview(answer)
        content.sound = .default
        content.threadIdentifier = pullRequest.description
        content.userInfo = [pullRequestKey: pullRequest.description, draftKey: draft?.uuidString ?? ""]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Review: notification not shown: \(error)") }
        }
    }

    /// The answer's first paragraph, without Markdown punctuation.
    static func preview(_ markdown: String) -> String {
        let first = markdown.components(separatedBy: "\n\n").first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? markdown
        let plain = first.replacingOccurrences(of: "`", with: "").replacingOccurrences(of: "**", with: "")
        return plain.count > 220 ? String(plain.prefix(220)) + "…" : plain
    }
}
