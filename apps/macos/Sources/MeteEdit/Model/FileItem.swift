import AppKit
import Foundation
import Observation

/// One file in the list: its providers, the values read from disk and the staged (unsaved) changes.
@Observable
final class FileItem: Identifiable {
    let id = UUID()
    private(set) var url: URL
    private(set) var providers: [any MetadataProvider] = []
    private(set) var specs: [FieldSpec] = []
    /// Provider id that owns each field (General fields are shared keys, so the owner is not in the key).
    private(set) var owners: [FieldKey: String] = [:]
    private(set) var values: [FieldKey: FieldValue] = [:]
    /// Staged changes. A key present with a nil value means "remove this tag".
    private(set) var staged: [FieldKey: FieldValue?] = [:]
    private(set) var isWritable = true
    var error: String?

    init(url: URL) {
        self.url = url
    }

    var name: String { url.lastPathComponent }
    var directory: String { url.deletingLastPathComponent().path }
    var isDirty: Bool { !staged.isEmpty }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    func load() {
        providers = ProviderRegistry.providers(for: url)
        isWritable = FileManager.default.isWritableFile(atPath: url.path)
        var specs: [FieldSpec] = []
        var owners: [FieldKey: String] = [:]
        var values: [FieldKey: FieldValue] = [:]
        var errors: [String] = []
        for provider in providers {
            do {
                let data = try provider.read(url: url)
                for spec in data.specs where owners[spec.key] == nil {
                    specs.append(spec)
                    owners[spec.key] = provider.id
                }
                values.merge(data.values) { old, _ in old }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if !isWritable {
            specs = specs.map { spec in
                var copy = spec
                copy.writable = false
                return copy
            }
        }
        self.specs = specs
        self.owners = owners
        self.values = values
        self.error = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func spec(for key: FieldKey) -> FieldSpec? { specs.first { $0.key == key } }
    func supports(_ key: FieldKey) -> Bool { specs.contains { $0.key == key } }

    /// Value as the user currently sees it: staged change if any, otherwise what is on disk.
    func currentValue(for key: FieldKey) -> FieldValue? {
        if let staged = staged[key] { return staged }
        return values[key]
    }

    /// Stages a value. Staging the original value again removes the staged change.
    func stage(_ value: FieldValue?, for key: FieldKey) {
        guard supports(key) else { return }
        let normalized = (value?.isEmpty ?? true) ? nil : value
        if normalized == values[key] {
            staged.removeValue(forKey: key)
        } else {
            staged[key] = .some(normalized)
        }
    }

    func revert(_ key: FieldKey) { staged.removeValue(forKey: key) }
    func revertAll() { staged = [:] }

    /// Writes staged changes through every provider, then re-reads the file.
    func save(preserveModificationDate: Bool, onlyWhereEmpty: Set<FieldKey>) throws {
        var changes = staged
        for key in onlyWhereEmpty where changes[key] != nil {
            if let existing = values[key], !existing.isEmpty { changes.removeValue(forKey: key) }
        }
        guard !changes.isEmpty else {
            staged = [:]
            return
        }
        let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let touchesDates = changes.keys.contains {
            $0.provider == FileAttributesProvider.providerID && ($0.id == "modified" || $0.id == "created")
        }
        var current = url
        for provider in providers {
            let mine = changes.filter { owners[$0.key] == provider.id }
            guard !mine.isEmpty else { continue }
            current = try provider.write(url: current, changes: mine)
        }
        if preserveModificationDate, !touchesDates, let modificationDate {
            var resourceValues = URLResourceValues()
            resourceValues.contentModificationDate = modificationDate
            var target = current
            try? target.setResourceValues(resourceValues)
        }
        url = current
        staged = [:]
        error = nil
        load()
    }
}
