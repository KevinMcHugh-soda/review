import ReviewKit
import SwiftUI

/// References, implementations or callers, below the code — Xcode's find
/// navigator shape, so the file under review stays in view.
struct ResultsPanel: View {
    @Bindable var session: ReviewSession
    let results: NavigationResults

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.spacing) {
                Text(results.title)
                    .font(Theme.Fonts.panelTitle)
                    .lineLimit(1)
                Spacer()
                Button("Close Results", systemImage: "xmark") { session.results = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Close (Esc)")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, Theme.tightSpacing)
            .background(.bar)
            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch results {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(_, let message):
            Text(message)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(Theme.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .locations(_, let groups):
            if groups.isEmpty {
                Text("Nothing found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section(group.displayPath) {
                            ForEach(group.items) { item in
                                LocationRow(item: item) { session.open(item.location) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        case .callers(_, let root):
            List {
                CallerRow(node: root, session: session)
            }
            .listStyle(.inset)
        }
    }
}
