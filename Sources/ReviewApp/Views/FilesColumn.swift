import ReviewDiff
import ReviewKit
import SwiftUI

/// The selected pull request's changed files, or where loading has got to.
struct FilesColumn: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: ReviewSession

    var body: some View {
        switch session.phase {
        case .loading(let step):
            ProgressView {
                Text(step?.rawValue ?? "Starting")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't Open \(session.reference.description)", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
                    .textSelection(.enabled)
            } actions: {
                Button("Try Again") {
                    Task { await model.load(session) }
                }
            }
        case .loaded(let review):
            List(review.files, selection: $session.selectedFilePath) { file in
                FileRow(file: file)
                    .tag(file.path)
            }
            .overlay {
                if review.files.isEmpty {
                    ContentUnavailableView("No Changes", systemImage: "checkmark.circle")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FilesFooter(files: review.files)
            }
        }
    }
}
