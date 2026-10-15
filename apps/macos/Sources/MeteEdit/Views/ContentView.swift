import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            FileListView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 480)
        } detail: {
            EditorView()
        }
        .searchable(text: $state.filterText, placement: .sidebar, prompt: "Filter files")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { state.openPanel() } label: { Label("Add Files…", systemImage: "plus") }
                    .help("Add files or folders (⌘O)")
                Button { state.removeSelected() } label: { Label("Remove", systemImage: "minus") }
                    .disabled(state.selection.isEmpty)
                    .help("Remove from list")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { state.saveSelected() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .disabled(!state.selectionIsDirty)
                    .help("Save selected files (⌘S)")
                Button { state.saveAll() } label: { Label("Save All", systemImage: "square.and.arrow.down.on.square") }
                    .disabled(state.dirtyFiles.isEmpty)
                    .help("Save all changed files (⇧⌘S)")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.addURLs(urls)
            return true
        }
        .sheet(item: $state.pendingSave) { request in
            SaveConfirmationView(request: request)
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Toggle("Preserve file modification date when saving", isOn: $state.preserveModificationDate)
            Text("When on, writing tags does not change the date shown in Finder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 440)
    }
}
