import ReviewDiff
import SwiftUI

/// Which file the viewer is showing, and whether it is part of the PR — a
/// jump can land anywhere, and the eye needs to know it has left the change.
struct FileHeader: View {
    let session: ReviewSession

    var body: some View {
        HStack(spacing: Theme.spacing) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(path)
                .font(Theme.Fonts.panelTitle)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            Spacer(minLength: Theme.spacing)
            Text(note)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let file = session.selectedFile, session.externalFile == nil {
                FileCounts(file: file)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.tightSpacing)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var path: String {
        if let external = session.externalFile { session.displayPath(for: external) } else { session.selectedFile?.path ?? "" }
    }

    private var isInsideCheckout: Bool {
        guard let external = session.externalFile, let worktree = session.worktree else { return true }
        return external.standardizedFileURL.path.hasPrefix(worktree.standardizedFileURL.path + "/")
    }

    private var symbol: String {
        session.externalFile == nil ? "doc.text" : (isInsideCheckout ? "doc" : "shippingbox")
    }

    private var note: String {
        if session.externalFile != nil {
            return isInsideCheckout ? "Not changed in this PR" : "Outside the repository"
        }
        guard let file = session.selectedFile else { return "" }
        return switch file.status {
        case .added: "Added"
        case .deleted: "Deleted"
        case .renamed: "Renamed from \(file.oldPath ?? "")"
        case .modified: "Modified"
        }
    }
}
