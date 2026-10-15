import SwiftUI

/// Keyboard shortcuts, defined once for the menus and for the help texts that mention them.
@MainActor
enum Shortcut {
    static let open = KeyboardShortcut("o")
    static let addFolder = KeyboardShortcut("o", modifiers: [.command, .shift])
    static let selectAllFiles = KeyboardShortcut("a", modifiers: [.command, .shift])
    static let deselectAll = KeyboardShortcut("a", modifiers: [.command, .shift, .option])
    static let save = KeyboardShortcut("s")
    static let saveAll = KeyboardShortcut("s", modifiers: [.command, .shift])
    static let removeFromList = KeyboardShortcut(.delete, modifiers: .command)
}

extension KeyboardShortcut {
    /// The shortcut as menus show it, such as "⇧⌘S".
    var symbols: String {
        let modifierSymbols: [(EventModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let modifierText = modifierSymbols.filter { modifiers.contains($0.0) }.map(\.1).joined()
        let keyText = key == .delete ? "⌫" : String(key.character).uppercased()
        return modifierText + keyText
    }
}
