import ReviewKit
import SwiftUI

/// A caller in the tree; expanding it asks for its own callers.
struct CallerRow: View {
    @Bindable var node: CallerTreeNode
    let session: ReviewSession

    var body: some View {
        DisclosureGroup(isExpanded: $node.isExpanded) {
            if node.isLoading {
                ProgressView().controlSize(.small)
            } else if let error = node.error {
                Text(error).foregroundStyle(.secondary)
            } else if let children = node.children {
                if children.isEmpty {
                    Text("No callers")
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(.secondary)
                }
                ForEach(children) { child in
                    CallerRow(node: child, session: session)
                }
            }
        } label: {
            Button {
                session.open(node.caller.callSites.first ?? node.caller.location)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
                    Text(node.caller.name)
                        .font(Theme.Fonts.codeSmall.weight(.semibold))
                        .lineLimit(1)
                    Text(location)
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(node.caller.callSites.isEmpty ? "Go to the declaration" : "Go to the call")
        }
        .onChange(of: node.isExpanded, initial: true) {
            guard node.isExpanded, let navigator = session.navigator else { return }
            Task { await node.loadChildren(using: navigator) }
        }
    }

    private var location: String {
        let site = node.caller.callSites.first ?? node.caller.location
        let path = session.displayPath(for: site.file)
        return "\(path):\(site.line)"
    }
}
