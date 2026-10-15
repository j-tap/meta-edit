import AppKit
import SwiftUI

@main
struct MetaEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let state = AppState.shared
    private let localizer = Localizer.shared

    var body: some Scene {
        Window("MetaEdit", id: "main") {
            ContentView()
                .environment(state)
                .environment(\.locale, localizer.locale)
                .frame(minWidth: 860, minHeight: 540)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(tr("Open…")) { state.openPanel() }
                    .keyboardShortcut("o")
                Button(tr("Add Folder…")) { state.openPanel(directoriesOnly: true) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button(tr("Select All Files")) { state.selection = Set(state.filteredFiles.map(\.id)) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(state.files.isEmpty)
                Button(tr("Deselect All")) { state.selection = [] }
                    .keyboardShortcut("a", modifiers: [.command, .shift, .option])
                    .disabled(state.selection.isEmpty)
            }
            CommandGroup(replacing: .saveItem) {
                Button(tr("Save")) { state.saveSelected() }
                    .keyboardShortcut("s")
                    .disabled(!state.selectionIsDirty || state.isSaving)
                Button(tr("Save All")) { state.saveAll() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(state.dirtyFiles.isEmpty || state.isSaving)
                Divider()
                Button(tr("Revert Selected")) { state.revertSelected() }
                    .disabled(!state.selectionIsDirty)
                Button(tr("Revert All")) { state.revertAll() }
                    .disabled(state.dirtyFiles.isEmpty)
                Divider()
                Button(tr("Remove from List")) { state.removeSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(state.selection.isEmpty)
            }
        }
        Settings {
            SettingsView()
                .environment(state)
                .environment(localizer)
                .environment(\.locale, localizer.locale)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        AppState.shared.addURLs(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppState.shared.terminateReply()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
