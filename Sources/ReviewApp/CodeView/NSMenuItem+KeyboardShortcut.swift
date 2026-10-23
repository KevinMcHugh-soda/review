import AppKit
import SwiftUI

extension NSMenuItem {
    /// Shows a SwiftUI shortcut beside the item, as the menu bar does. A
    /// context menu is only consulted while it is open, so this labels the
    /// item without binding the key a second time.
    func showShortcut(_ shortcut: KeyboardShortcut) {
        keyEquivalent = String(shortcut.key.character)
        keyEquivalentModifierMask = NSEvent.ModifierFlags(shortcut.modifiers)
    }
}

extension NSEvent.ModifierFlags {
    init(_ modifiers: EventModifiers) {
        self = []
        if modifiers.contains(.command) { insert(.command) }
        if modifiers.contains(.shift) { insert(.shift) }
        if modifiers.contains(.option) { insert(.option) }
        if modifiers.contains(.control) { insert(.control) }
    }
}
