import ReviewLSP
import SwiftUI

/// One quiet line under the code: whether navigation is ready, what each
/// server is doing, and the last thing navigation had to say.
struct NavigationStatusBar: View {
    let session: ReviewSession

    var body: some View {
        HStack(spacing: Theme.spacing) {
            switch session.navigationState {
            case .preparing:
                ProgressView().controlSize(.mini)
                Text("Checking out for navigation…")
            case .unavailable(let reason):
                Image(systemName: "exclamationmark.triangle")
                Text(reason).lineLimit(1).truncationMode(.tail)
            case .ready:
                ForEach(ServerKind.allCases.filter { session.serverStatus[$0] != nil }, id: \.self) { kind in
                    ServerStatusLabel(kind: kind, status: session.serverStatus[kind] ?? .starting)
                }
            }
            Spacer(minLength: Theme.spacing)
            if let message = session.navigationMessage {
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(Theme.Fonts.meta)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.tightSpacing)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

private struct ServerStatusLabel: View {
    let kind: ServerKind
    let status: LanguageServer.Status

    var body: some View {
        HStack(spacing: Theme.tightSpacing) {
            switch status {
            case .starting:
                ProgressView().controlSize(.mini)
                Text("\(kind.displayName) starting")
            case .indexing(let title):
                ProgressView().controlSize(.mini)
                Text("\(kind.displayName): \(title)")
            case .ready:
                Image(systemName: "checkmark.circle")
                Text(kind.displayName)
            case .failed(let reason):
                Image(systemName: "xmark.circle")
                Text("\(kind.displayName) failed")
                    .help(reason)
            }
        }
        .lineLimit(1)
    }
}
