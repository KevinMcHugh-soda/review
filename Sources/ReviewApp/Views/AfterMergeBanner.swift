import SwiftUI

/// Says why the whole-file view differs from the PR branch, and why
/// navigation is off in it.
struct AfterMergeBanner: View {
    let baseName: String

    var body: some View {
        Label {
            Text("As it will be after merging: \(baseName) has changed this file since the PR branched. Navigation works in Diff view (⌘1).")
                .lineLimit(2)
        } icon: {
            Image(systemName: "arrow.triangle.merge")
        }
        .font(Theme.Fonts.meta)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.tightSpacing)
        .background(.bar)
    }
}
