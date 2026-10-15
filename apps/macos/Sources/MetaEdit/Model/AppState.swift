import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    private static let preserveModificationDateKey = "preserveModificationDate"
    /// How long a status message replaces the file count under the list.
    private static let statusDuration: Duration = .seconds(4)

    var files: [FileItem] = []
    var selection: Set<UUID> = []
    var filterText = ""
    var pendingSave: SaveRequest?
    private(set) var status: String?
    var preserveModificationDate: Bool {
        didSet { UserDefaults.standard.set(preserveModificationDate, forKey: Self.preserveModificationDateKey) }
    }

    private let loads = SerialTaskQueue()
    private let saves = SerialTaskQueue()
    @ObservationIgnored private var statusReset: Task<Void, Never>?

    init() {
        preserveModificationDate = UserDefaults.standard.object(forKey: Self.preserveModificationDateKey) as? Bool ?? true
    }

    var isLoading: Bool { loads.isBusy }
    var isSaving: Bool { saves.isBusy }

    var filteredFiles: [FileItem] {
        let query = filterText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return files }
        return files.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.directory.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedFiles: [FileItem] { files.filter { selection.contains($0.id) } }
    var dirtyFiles: [FileItem] { files.filter(\.isDirty) }
    var selectionIsDirty: Bool { selectedFiles.contains(where: \.isDirty) }
    var canSaveSelected: Bool { !isSaving && selectionIsDirty }
    var canSaveAll: Bool { !isSaving && files.contains(where: \.isDirty) }

    func selectAllListed() { selection = Set(filteredFiles.map(\.id)) }

    /// Shows `message` under the list for a few seconds, then the file count again.
    private func showStatus(_ message: String) {
        status = message
        statusReset?.cancel()
        statusReset = Task {
            try? await Task.sleep(for: Self.statusDuration)
            guard !Task.isCancelled else { return }
            status = nil
        }
    }

    // MARK: Adding files

    /// Adds files and the contents of folders in the background. The returned task finishes when they are in the list.
    @discardableResult
    func addURLs(_ urls: [URL]) -> Task<Void, Never> {
        loads.enqueue { await self.load(urls) }
    }

    private func load(_ urls: [URL]) async {
        let expanded = await Task.detached(priority: .userInitiated) { Self.expand(urls) }.value
        // Loads are queued, so the list already holds everything earlier loads added.
        var seen = Set(files.map { $0.url.standardizedFileURL.path })
        let fresh = expanded.filter { seen.insert($0.standardizedFileURL.path).inserted }
        let skipped = expanded.count - fresh.count
        var added: [FileItem] = []
        // Files are read several at a time and join the list in order as they are ready.
        await mapConcurrently(fresh, transform: { FileItem.read($0) }) { url, snapshot in
            let item = FileItem(url: url)
            item.apply(snapshot)
            files.append(item)
            added.append(item)
        }
        if selection.isEmpty, let first = added.first {
            selection = [first.id]
        }
        if added.isEmpty {
            showStatus(skipped > 0 ? tr("Already in the list") : tr("No files found"))
        } else {
            showStatus(trPlural("Added %d files", added.count))
        }
    }

    nonisolated private static func expand(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = fm.enumerator(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                var found: [URL] = []
                for case let child as URL in enumerator {
                    if (try? child.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                        found.append(child)
                    }
                }
                result.append(contentsOf: found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
            } else {
                result.append(url)
            }
        }
        return result
    }

    // MARK: Removing and reverting

    func remove(_ ids: Set<UUID>) {
        let dirty = files.filter { ids.contains($0.id) && $0.isDirty }
        switch askAboutUnsavedChanges(dirty) {
        case .cancel:
            break
        case .discard:
            removeFromList(ids)
        case .save:
            Task {
                if await saveBeforeClosing(dirty) { removeFromList(ids) }
            }
        }
    }

    private func removeFromList(_ ids: Set<UUID>) {
        files.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    func removeSelected() { remove(selection) }
    func revert(_ files: [FileItem]) { files.forEach { $0.revertAll() } }
    func revertSelected() { revert(selectedFiles) }
    func revertAll() { revert(files) }

    // MARK: Editing

    func stage(_ value: FieldValue?, for key: FieldKey, in files: [FileItem]) {
        for file in files where file.supports(key) {
            file.stage(value, for: key)
        }
    }

    func revert(_ key: FieldKey, in files: [FileItem]) {
        files.forEach { $0.revert(key) }
    }

    // MARK: Saving

    func requestSave(_ candidates: [FileItem]) {
        let affected = candidates.filter(\.isDirty)
        guard !affected.isEmpty else { return }
        if affected.count > 1 {
            pendingSave = SaveRequest(files: affected)
        } else {
            performSave(affected, onlyWhereEmpty: [])
        }
    }

    func saveSelected() { requestSave(selectedFiles) }
    func saveAll() { requestSave(files) }

    /// Writes the files one at a time in the background. Saves queue up behind each other.
    /// The returned task finishes when this save is done.
    @discardableResult
    func performSave(_ files: [FileItem], onlyWhereEmpty: Set<FieldKey>) -> Task<Void, Never> {
        saves.enqueue { await self.write(files, onlyWhereEmpty: onlyWhereEmpty) }
    }

    private func write(_ files: [FileItem], onlyWhereEmpty: Set<FieldKey>) async {
        var failed = 0
        for file in files {
            do {
                try await file.save(preserveModificationDate: preserveModificationDate, onlyWhereEmpty: onlyWhereEmpty)
            } catch {
                failed += 1
            }
        }
        let saved = files.count - failed
        showStatus(failed == 0 ? trPlural("Saved %d files", saved) : tr("Saved %d, failed %d", saved, failed))
    }

    // MARK: Panels and dialogs

    func openPanel(directoriesOnly: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directoriesOnly
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = directoriesOnly ? tr("Choose folders to add") : tr("Choose files or folders to add")
        panel.prompt = tr("Add")
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    enum UnsavedChangesDecision {
        case save, discard, cancel
    }

    /// Asks what to do with unsaved changes in `dirty`. With nothing unsaved the answer is `.discard` without asking.
    func askAboutUnsavedChanges(_ dirty: [FileItem]) -> UnsavedChangesDecision {
        guard !dirty.isEmpty else { return .discard }
        let alert = NSAlert()
        alert.messageText = trPlural("Save changes to %d files?", dirty.count)
        alert.informativeText = tr("Your changes will be lost if you don't save them.")
        alert.addButton(withTitle: tr("Save"))
        alert.addButton(withTitle: tr("Cancel"))
        alert.addButton(withTitle: tr("Don't Save"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }

    /// Saves `dirty` and tells whether every file was written, so the caller may close them.
    func saveBeforeClosing(_ dirty: [FileItem]) async -> Bool {
        await performSave(dirty, onlyWhereEmpty: []).value
        return !dirty.contains(where: \.isDirty)
    }

    /// Answer for NSApplicationDelegate.applicationShouldTerminate: asks about unsaved changes and saves them first if wanted.
    func terminateReply() -> NSApplication.TerminateReply {
        let dirty = dirtyFiles
        switch askAboutUnsavedChanges(dirty) {
        case .cancel:
            return .terminateCancel
        case .discard:
            return .terminateNow
        case .save:
            Task {
                NSApp.reply(toApplicationShouldTerminate: await saveBeforeClosing(dirty))
            }
            return .terminateLater
        }
    }
}

/// A multi-file save waiting for confirmation. See docs/batch-editing.md.
@MainActor
struct SaveRequest: Identifiable {
    let id = UUID()
    let files: [FileItem]

    struct Entry: Identifiable {
        let spec: FieldSpec
        let value: FieldValue?
        let isUniform: Bool
        let count: Int
        var id: FieldKey { spec.key }
    }

    var entries: [Entry] {
        var byKey: [FieldKey: (spec: FieldSpec, values: [FieldValue?])] = [:]
        var order: [FieldKey] = []
        for file in files {
            for (key, value) in file.staged {
                guard let spec = file.spec(for: key) else { continue }
                if byKey[key] == nil {
                    byKey[key] = (spec, [])
                    order.append(key)
                }
                byKey[key]?.values.append(value)
            }
        }
        return order.compactMap { key -> Entry? in
            guard let entry = byKey[key] else { return nil }
            let distinct = Set(entry.values)
            return Entry(spec: entry.spec, value: entry.values.first ?? nil, isUniform: distinct.count == 1, count: entry.values.count)
        }
        .sorted { ($0.spec.group, $0.spec.order) < ($1.spec.group, $1.spec.order) }
    }
}
