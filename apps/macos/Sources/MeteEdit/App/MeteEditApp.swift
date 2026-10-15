import AppKit
import SwiftUI

@main
struct MeteEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let state = AppState.shared

    var body: some Scene {
        Window("MeteEdit", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 860, minHeight: 540)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { state.openPanel() }
                    .keyboardShortcut("o")
                Button("Add Folder…") { state.openPanel(directoriesOnly: true) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Select All Files") { state.selection = Set(state.filteredFiles.map(\.id)) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(state.files.isEmpty)
                Button("Deselect All") { state.selection = [] }
                    .keyboardShortcut("a", modifiers: [.command, .shift, .option])
                    .disabled(state.selection.isEmpty)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { state.saveSelected() }
                    .keyboardShortcut("s")
                    .disabled(!state.selectionIsDirty)
                Button("Save All") { state.saveAll() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(state.dirtyFiles.isEmpty)
                Divider()
                Button("Revert Selected") { state.revertSelected() }
                    .disabled(!state.selectionIsDirty)
                Button("Revert All") { state.revertAll() }
                    .disabled(state.dirtyFiles.isEmpty)
                Divider()
                Button("Remove from List") { state.removeSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(state.selection.isEmpty)
            }
        }
        Settings {
            SettingsView().environment(state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        AppState.shared.addURLs(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppState.shared.confirmDiscardingChanges() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
