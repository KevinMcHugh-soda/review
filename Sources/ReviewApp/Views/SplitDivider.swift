import SwiftUI

/// The draggable line between the code and the results panel.
///
/// The visible rule is a hairline, but the hit area is deliberately taller —
/// a one-pixel drag target is unusable. Used inside a `VStack` rather than a
/// `VSplitView`, which proposes an unspecified width to its children (uncurl
/// lost three layouts to that).
struct SplitDivider: View {
    let isDragging: Bool

    var body: some View {
        ZStack {
            Color.clear
                .frame(height: Theme.dividerHitHeight)
                .contentShape(.rect)
            Rectangle()
                .fill(isDragging ? Color.accentColor : Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
        .frame(height: Theme.dividerHitHeight)
        .onHover { hovering in
            // The resize cursor is the affordance; without it the divider
            // looks like decoration.
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Resize the results panel")
    }
}
