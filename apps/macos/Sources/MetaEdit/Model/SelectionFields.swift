import Foundation

struct ValueCount: Hashable {
    let value: FieldValue?
    let count: Int
}

enum OriginalState: Equatable {
    /// Every selected file has this value (nil = none of them has the tag).
    case same(FieldValue?)
    /// Values differ; distinct values with counts, most common first.
    case mixed([ValueCount])
}

enum PendingState: Equatable {
    case none
    /// Every selected file has the same staged value.
    case uniform(FieldValue?)
    /// Only some files have a staged value, or staged values differ.
    case partial
}

/// One field as shown for the current selection. See docs/batch-editing.md.
struct FieldState: Identifiable {
    let spec: FieldSpec
    /// Translated label. A General field labelled differently per file type shows both, e.g. "Artist / Author".
    let label: String
    let supportCount: Int
    let total: Int
    let original: OriginalState
    let pending: PendingState

    var id: FieldKey { spec.key }

    var isPending: Bool {
        if case .none = pending { return false }
        return true
    }

    var isMixed: Bool {
        switch pending {
        case .partial: return true
        case .uniform: return false
        case .none:
            if case .mixed = original { return true }
            return false
        }
    }

    var displayValue: FieldValue? {
        switch pending {
        case .uniform(let value): return value
        case .partial: return nil
        case .none:
            if case .same(let value) = original { return value }
            return nil
        }
    }

    var mixedValues: [ValueCount] {
        if case .mixed(let values) = original { return values }
        return []
    }
}

struct FieldGroupState: Identifiable {
    let group: FieldGroup
    let fields: [FieldState]
    var id: FieldGroup { group }
}

@MainActor
enum SelectionFields {
    static func compute(_ files: [FileItem]) -> [FieldGroupState] {
        guard !files.isEmpty else { return [] }
        var specs: [FieldKey: FieldSpec] = [:]
        var order: [FieldKey] = []
        var labels: [FieldKey: [String]] = [:]
        var originals: [FieldKey: [FieldValue?]] = [:]
        var staged: [FieldKey: [FieldValue??]] = [:]

        for file in files {
            for spec in file.specs {
                if files.count > 1, spec.key == FileAttributesProvider.nameKey { continue }
                if specs[spec.key] == nil {
                    specs[spec.key] = spec
                    order.append(spec.key)
                }
                if labels[spec.key]?.contains(spec.displayLabel) != true {
                    labels[spec.key, default: []].append(spec.displayLabel)
                }
                originals[spec.key, default: []].append(file.values[spec.key])
                staged[spec.key, default: []].append(file.staged[spec.key])
            }
        }

        var groups: [FieldGroup: [FieldState]] = [:]
        for key in order {
            guard let spec = specs[key], let origs = originals[key], let stagedEntries = staged[key] else { continue }
            let counts = Dictionary(grouping: origs, by: { $0 })
                .map { ValueCount(value: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count }
            let original: OriginalState = counts.count <= 1 ? .same(origs.first ?? nil) : .mixed(counts)

            let present = stagedEntries.compactMap { $0 }
            let pending: PendingState
            if present.isEmpty {
                pending = .none
            } else if present.count == stagedEntries.count, Set(present).count == 1 {
                pending = .uniform(present[0])
            } else {
                pending = .partial
            }
            groups[spec.group, default: []].append(
                FieldState(spec: spec, label: (labels[key] ?? []).joined(separator: " / "), supportCount: origs.count, total: files.count, original: original, pending: pending)
            )
        }
        return groups.keys.sorted().map { group in
            FieldGroupState(group: group, fields: groups[group]!.sorted { ($0.spec.order, $0.label) < ($1.spec.order, $1.label) })
        }
    }
}
