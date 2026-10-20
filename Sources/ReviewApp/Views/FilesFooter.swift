import ReviewDiff
import SwiftUI

/// "14 files · +320 −41" under the file list.
struct FilesFooter: View {
    let files: [FileDiff]

    var body: some View {
        let additions = files.reduce(0) { $0 + $1.additions }
        let deletions = files.reduce(0) { $0 + $1.deletions }
        Text("^[\(files.count) file](inflect: true) · +\(additions) −\(deletions)")
            .font(Theme.Fonts.meta)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, Theme.spacing)
            .background(.bar)
    }
}
