import ReviewCore
import SwiftUI

/// One repository to browse. Its menu tracks or untracks it, which decides
/// whether its pull requests reach the sidebar's inbox.
struct BrowseRepositoryRow: View {
    let repository: RepositoryName
    let isTracked: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(repository.description)
            .lineLimit(1)
            .truncationMode(.middle)
            .tag(BrowseScope.repository(repository))
            .help(repository.description)
            .contextMenu {
                if let url = URL(string: "https://github.com/\(repository)/pulls") {
                    Link("Open on GitHub", destination: url)
                }
                Divider()
                if isTracked {
                    Button("Stop Tracking") { model.untrack([repository]) }
                } else {
                    Button("Track Repository") { try? model.track(repository.description) }
                }
            }
    }
}
