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
        .searchable(text: $state.filterText, placement: .sidebar, prompt: Text(tr("Filter files")))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { state.openPanel() } label: { Label(tr("Add Files…"), systemImage: "plus") }
                    .help(tr("Add files or folders (⌘O)"))
                Button { state.removeSelected() } label: { Label(tr("Remove"), systemImage: "minus") }
                    .disabled(state.selection.isEmpty)
                    .help(tr("Remove from list"))
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { state.saveSelected() } label: { Label(tr("Save"), systemImage: "square.and.arrow.down") }
                    .disabled(!state.selectionIsDirty || state.isSaving)
                    .help(tr("Save selected files (⌘S)"))
                Button { state.saveAll() } label: { Label(tr("Save All"), systemImage: "square.and.arrow.down.on.square") }
                    .disabled(state.dirtyFiles.isEmpty || state.isSaving)
                    .help(tr("Save all changed files (⇧⌘S)"))
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
    @Environment(Localizer.self) private var localizer

    var body: some View {
        @Bindable var state = state
        @Bindable var localizer = localizer
        Form {
            Picker(tr("Language"), selection: $localizer.choice) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.nativeName).tag(language)
                }
            }
            Text(tr("Menus provided by macOS switch after the app is restarted."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Toggle(tr("Preserve file modification date when saving"), isOn: $state.preserveModificationDate)
            Text(tr("When on, writing tags does not change the date shown in Finder."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 440)
    }
}
