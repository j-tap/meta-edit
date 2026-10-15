import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var files: [FileItem] = []
    var selection: Set<UUID> = []
    var filterText = ""
    var pendingSave: SaveRequest?
    var isLoading = false
    var isSaving = false
    var status: String?
    var preserveModificationDate: Bool {
        didSet { UserDefaults.standard.set(preserveModificationDate, forKey: "preserveModificationDate") }
    }

    init() {
        preserveModificationDate = UserDefaults.standard.object(forKey: "preserveModificationDate") as? Bool ?? true
    }

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

    // MARK: Adding files

    func addURLs(_ urls: [URL]) {
        Task { await load(urls) }
    }

    private func load(_ urls: [URL]) async {
        isLoading = true
        defer { isLoading = false }
        var seen = Set(files.map { $0.url.standardizedFileURL.path })
        let expanded = await Task.detached(priority: .userInitiated) { Self.expand(urls) }.value
        var added: [FileItem] = []
        var skipped = 0
        for url in expanded {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else {
                skipped += 1
                continue
            }
            seen.insert(path)
            let item = await Task.detached(priority: .userInitiated) {
                let item = FileItem(url: url)
                item.load()
                return item
            }.value
            files.append(item)
            added.append(item)
        }
        if selection.isEmpty, let first = added.first {
            selection = [first.id]
        }
        if added.isEmpty {
            status = skipped > 0 ? "Already in the list" : "No files found"
        } else {
            status = "Added \(added.count) file\(added.count == 1 ? "" : "s")"
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
        if !dirty.isEmpty, !confirmDiscardingChanges(dirty) { return }
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

    func performSave(_ files: [FileItem], onlyWhereEmpty: Set<FieldKey>) {
        isSaving = true
        var failed = 0
        for file in files {
            do {
                try file.save(preserveModificationDate: preserveModificationDate, onlyWhereEmpty: onlyWhereEmpty)
            } catch {
                file.error = error.localizedDescription
                failed += 1
            }
        }
        isSaving = false
        let saved = files.count - failed
        status = failed == 0
            ? "Saved \(saved) file\(saved == 1 ? "" : "s")"
            : "Saved \(saved), failed \(failed)"
    }

    // MARK: Panels and dialogs

    func openPanel(directoriesOnly: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directoriesOnly
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = directoriesOnly ? "Choose folders to add" : "Choose files or folders to add"
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    /// Asks what to do with unsaved changes. Returns true when the caller may proceed.
    func confirmDiscardingChanges(_ dirty: [FileItem]? = nil) -> Bool {
        let dirty = dirty ?? dirtyFiles
        guard !dirty.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(dirty.count) file\(dirty.count == 1 ? "" : "s")?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            performSave(dirty, onlyWhereEmpty: [])
            return !dirty.contains(where: \.isDirty)
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }
}

/// A multi-file save waiting for confirmation. See docs/batch-editing.md.
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
