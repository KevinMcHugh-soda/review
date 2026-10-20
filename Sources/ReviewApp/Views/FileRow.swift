import ReviewDiff
import SwiftUI

/// A changed file: its status, its name with the directory quieter beneath,
/// and its line counts.
struct FileRow: View {
    let file: FileDiff
    var isGenerated = false
    @Binding var isViewed: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityLabel(file.status.rawValue.capitalized)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.Fonts.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !directory.isEmpty {
                    Text(directory)
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: Theme.tightSpacing)
            if isGenerated {
                StateTag(text: "generated")
                    .help("Marked linguist-generated in .gitattributes; collapsed in the all-files view")
            }
            FileCounts(file: file)
            Toggle("Viewed", isOn: $isViewed)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(isViewed ? "Viewed — unmark (⌥⌘V)" : "Mark as viewed (⌥⌘V)")
        }
        .opacity(isViewed ? 0.55 : 1)
        .help(helpText)
    }

    private var name: String { (file.path as NSString).lastPathComponent }

    private var directory: String {
        let parent = (file.path as NSString).deletingLastPathComponent
        guard file.status == .renamed, let old = file.oldPath else { return parent }
        return "from \(old)"
    }

    private var helpText: String {
        if file.status == .renamed, let old = file.oldPath { "\(old) → \(file.path)" } else { file.path }
    }

    private var symbol: String {
        switch file.status {
        case .added: "plus.square.fill"
        case .deleted: "minus.square.fill"
        case .renamed: "arrow.right.square.fill"
        case .modified: "square.fill"
        }
    }

    private var tint: Color {
        switch file.status {
        case .added: .green
        case .deleted: .red
        case .renamed: .blue
        case .modified: .orange
        }
    }
}
