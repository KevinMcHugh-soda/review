import ReviewCore
import SwiftUI

/// Paste a PR URL or `owner/repo#123`, press Return.
struct OpenPullRequestField: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var isInvalid = false

    var body: some View {
        TextField("Pull request URL or owner/repo#123", text: $text)
            .textFieldStyle(.roundedBorder)
            .onSubmit(submit)
            .onChange(of: text) { isInvalid = false }
            .overlay(alignment: .trailing) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .padding(.trailing, Theme.tightSpacing)
                    .opacity(isInvalid ? 1 : 0)
                    .accessibilityLabel("Not a pull request URL")
                    .accessibilityHidden(!isInvalid)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, Theme.spacing)
    }

    private func submit() {
        do {
            try model.open(text)
            text = ""
        } catch {
            isInvalid = true
        }
    }
}
