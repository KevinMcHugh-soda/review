import SwiftUI

/// What the reviewer can ask about the symbol under the cursor.
enum NavigationAction: String, CaseIterable, Identifiable {
    case definition
    case typeDefinition
    case references
    case implementations
    case callers

    var id: Self { self }

    var title: String {
        switch self {
        case .definition: "Jump to Definition"
        case .typeDefinition: "Jump to Type Definition"
        case .references: "Find References"
        case .implementations: "Find Implementations"
        case .callers: "Find Callers"
        }
    }

    /// Xcode's bindings where Xcode has one, so hands already know them.
    var shortcut: KeyboardShortcut {
        switch self {
        case .definition: KeyboardShortcut("j", modifiers: [.control, .command])
        case .typeDefinition: KeyboardShortcut("j", modifiers: [.control, .shift, .command])
        case .references: KeyboardShortcut("r", modifiers: [.control, .command])
        case .implementations: KeyboardShortcut("i", modifiers: [.control, .command])
        case .callers: KeyboardShortcut("h", modifiers: [.control, .shift, .command])
        }
    }
}
