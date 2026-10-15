import AppKit
import Foundation
import Observation

/// One file in the list: its providers, the values read from disk and the staged (unsaved) changes.
/// Reading and writing the file run off the main thread; their results are applied here on the main actor.
@MainActor
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

    // MARK: Reading

    /// What a read of the file found.
    struct Snapshot {
        var providers: [any MetadataProvider] = []
        var specs: [FieldSpec] = []
        var owners: [FieldKey: String] = [:]
        var values: [FieldKey: FieldValue] = [:]
        var isWritable = true
        var error: String?
    }

    /// Reads the file through every provider that supports it. Safe to call off the main thread.
    nonisolated static func read(_ url: URL) -> Snapshot {
        var snapshot = Snapshot()
        snapshot.providers = ProviderRegistry.providers(for: url)
        snapshot.isWritable = FileManager.default.isWritableFile(atPath: url.path)
        var errors: [String] = []
        for provider in snapshot.providers {
            do {
                let data = try provider.read(url: url)
                for spec in data.specs where snapshot.owners[spec.key] == nil {
                    snapshot.specs.append(spec)
                    snapshot.owners[spec.key] = provider.id
                }
                snapshot.values.merge(data.values) { old, _ in old }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if !snapshot.isWritable {
            snapshot.specs = snapshot.specs.map { spec in
                var copy = spec
                copy.writable = false
                return copy
            }
        }
        snapshot.error = errors.isEmpty ? nil : errors.joined(separator: "\n")
        return snapshot
    }

    /// Reads the file synchronously. The app loads files with `read(_:)` in the background instead.
    func load() {
        apply(Self.read(url))
    }

    func apply(_ snapshot: Snapshot) {
        providers = snapshot.providers
        specs = snapshot.specs
        owners = snapshot.owners
        values = snapshot.values
        isWritable = snapshot.isWritable
        error = snapshot.error
        // A staged value the file already holds is no longer a change, e.g. after a save that failed halfway.
        staged = staged.filter { key, value in value != values[key] }
    }

    // MARK: Editing

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

    // MARK: Saving

    /// Changes captured on the main actor, so the write itself can run in the background.
    private struct WritePlan {
        let url: URL
        let providers: [any MetadataProvider]
        let owners: [FieldKey: String]
        let changes: [FieldKey: FieldValue?]
        let preserveModificationDate: Bool

        /// Writes the changes through every provider and returns the file URL afterwards (it changes on rename).
        func run() throws -> URL {
            let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let touchesDates = !FileAttributesProvider.dateKeys.isDisjoint(with: changes.keys)
            var current = url
            for provider in providers {
                let mine = changes.filter { owners[$0.key] == provider.id }
                guard !mine.isEmpty else { continue }
                current = try provider.write(url: current, changes: mine)
            }
            if preserveModificationDate, !touchesDates, let modificationDate {
                var resourceValues = URLResourceValues()
                resourceValues.contentModificationDate = modificationDate
                try? current.setResourceValues(resourceValues)
            }
            return current
        }
    }

    /// Writes staged changes in the background, then re-reads the file.
    /// On success the written changes are unstaged; changes made while the write ran stay staged.
    /// On failure every change stays staged except those the file now holds, and `error` explains what went wrong.
    func save(preserveModificationDate: Bool, onlyWhereEmpty: Set<FieldKey>) async throws {
        let saving = staged
        let changes = saving.filter { key, _ in
            guard onlyWhereEmpty.contains(key), let existing = values[key] else { return true }
            return existing.isEmpty
        }
        guard !changes.isEmpty else {
            unstage(saving)
            return
        }
        let plan = WritePlan(
            url: url, providers: providers, owners: owners, changes: changes,
            preserveModificationDate: preserveModificationDate
        )
        let (result, snapshot) = await Task.detached(priority: .userInitiated) {
            let result = Result { try plan.run() }
            return (result, Self.read((try? result.get()) ?? plan.url))
        }.value
        switch result {
        case .success(let newURL):
            url = newURL
            unstage(saving)
            apply(snapshot)
        case .failure(let failure):
            apply(snapshot)
            error = failure.localizedDescription
            throw failure
        }
    }

    /// Removes staged changes that still hold the values in `changes`.
    private func unstage(_ changes: [FieldKey: FieldValue?]) {
        for (key, value) in changes where staged[key] == value {
            staged.removeValue(forKey: key)
        }
    }
}
