import Foundation
import ReviewCore

/// What the results panel below the code is showing.
enum NavigationResults {
    case loading(title: String)
    case locations(title: String, groups: [LocationGroup])
    case callers(title: String, root: CallerTreeNode)
    case failed(title: String, message: String)

    var title: String {
        switch self {
        case .loading(let title), .locations(let title, _), .callers(let title, _), .failed(let title, _): title
        }
    }
}

/// Results in one file.
struct LocationGroup: Identifiable {
    /// Relative to the checkout when inside it, else the absolute path.
    let displayPath: String
    let items: [LocationItem]

    var id: String { displayPath }
}

struct LocationItem: Identifiable, Hashable {
    let location: CodeLocation
    let snippet: String

    var id: CodeLocation { location }
}
