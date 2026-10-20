import Foundation
import Observation
import ReviewKit

/// One node of the callers tree. Children load when it is first expanded —
/// asking for every level up front would walk half the codebase.
@Observable
@MainActor
final class CallerTreeNode: Identifiable {
    let caller: Caller
    /// Nil until loaded.
    private(set) var children: [CallerTreeNode]?
    private(set) var isLoading = false
    private(set) var error: String?
    var isExpanded = false

    nonisolated var id: String { caller.id }

    init(caller: Caller) {
        self.caller = caller
    }

    func loadChildren(using navigator: Navigator) async {
        guard children == nil, !isLoading else { return }
        isLoading = true
        do {
            children = try await navigator.callers(of: caller).map(CallerTreeNode.init)
        } catch {
            self.error = "\(error)"
        }
        isLoading = false
    }
}
