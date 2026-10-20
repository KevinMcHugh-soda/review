import ReviewCore
import SwiftUI

/// Stands in for the review workspace until M2 builds it.
struct PullRequestPlaceholder: View {
    let reference: PullRequestReference

    var body: some View {
        ContentUnavailableView {
            Label(reference.description, systemImage: "arrow.triangle.pull")
        } description: {
            Text("The file list and code viewer arrive in milestone 2.")
        } actions: {
            Link("Open on GitHub", destination: reference.webURL)
        }
    }
}
