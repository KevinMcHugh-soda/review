import AppKit
import ReviewKit
import SwiftUI

/// The diff side by side: the base on the left, head on the right, scrolling
/// together.
///
/// The right pane is the document as the rest of the app knows it —
/// navigation, comments, hover. The left is for reading: it can be selected
/// and copied, and gaps expand from either side, but navigation runs on the
/// PR's head and comments on base lines are made in the unified diff.
struct SplitCodeView: NSViewRepresentable {
    let document: CodeDocument
    let documentID: String
    let scrollKey: String
    let reveal: Reveal?
    let draftRows: [Int: UUID]
    let threadRows: [Int: String]
    let actions: CodeViewActions

    @MainActor
    final class Coordinator {
        let left = CodePane()
        let right = CodePane()
        let container = NSStackView()
        private var isSyncing = false
        private var observers: [NSObjectProtocol] = []

        init() {
            container.orientation = .horizontal
            container.distribution = .fillEqually
            container.spacing = 1
            container.addArrangedSubview(left.scrollView)
            container.addArrangedSubview(right.scrollView)
            for (source, target) in [(left, right), (right, left)] {
                source.scrollView.contentView.postsBoundsChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: source.scrollView.contentView,
                    queue: .main
                ) { [weak self, weak source, weak target] _ in
                    MainActor.assumeIsolated {
                        guard let self, let source, let target else { return }
                        self.sync(from: source, to: target)
                    }
                })
            }
        }

        /// Vertical position follows the other pane; horizontal stays each
        /// pane's own, since long lines differ side to side.
        private func sync(from source: CodePane, to target: CodePane) {
            guard !isSyncing else { return }
            isSyncing = true
            defer { isSyncing = false }
            let clip = target.scrollView.contentView
            let y = source.scrollView.contentView.bounds.origin.y
            guard clip.bounds.origin.y != y else { return }
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            target.scrollView.reflectScrolledClipView(clip)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSStackView {
        context.coordinator.container
    }

    func updateNSView(_ container: NSStackView, context: Context) {
        let coordinator = context.coordinator
        coordinator.right.configureInteractive(actions)
        coordinator.left.textView.onExpandGap = actions.onExpandGap
        coordinator.left.textView.onHeaderClick = actions.onHeaderClick

        let leftRows = document.leftRows ?? []
        coordinator.left.show(leftRows, id: "left:\(documentID)", scrollKey: "left:\(scrollKey)")
        coordinator.right.show(document.rows, id: "right:\(documentID)", scrollKey: "right:\(scrollKey)")
        coordinator.right.textView.setMarks(drafts: draftRows, threads: threadRows)
        coordinator.right.apply(reveal, row: reveal?.row(in: document))
    }
}
