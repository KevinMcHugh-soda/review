import SwiftUI

extension KeyboardShortcut {
    /// Declared once so the menu bar and the code view's context menu show
    /// the same binding.
    static var addComment: KeyboardShortcut {
        KeyboardShortcut("m", modifiers: [.command, .shift])
    }
}
