import SwiftUI

/// Shown before writing more than one file. See docs/batch-editing.md.
struct SaveConfirmationView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let request: SaveRequest
    @ViewState private var onlyWhereEmpty: Set<FieldKey> = []
    @ViewState private var showFiles = false

    var body: some View {
        let entries = request.entries
        VStack(alignment: .leading, spacing: 12) {
            Text(trPlural("Change %d files?", request.files.count))
                .font(.title2.weight(.semibold))
            Text(tr("These fields will be written. Everything else in the files stays untouched."))
                .foregroundStyle(.secondary)
            List(entries) { entry in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.spec.displayLabel).fontWeight(.medium)
                        Text(description(for: entry))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(trPlural("%d files", entry.count))
                        .foregroundStyle(.secondary)
                    if entry.value != nil {
                        Toggle(tr("Only where empty"), isOn: binding(for: entry.spec.key))
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .help(tr("Skip files that already have a value in this field"))
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 140, maxHeight: 280)
            DisclosureGroup(tr("Files"), isExpanded: $showFiles) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(request.files) { file in
                            Text(file.name).font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            HStack {
                Spacer()
                Button(tr("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(trPlural("Change %d files", request.files.count)) {
                    state.performSave(request.files, onlyWhereEmpty: onlyWhereEmpty)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func description(for entry: SaveRequest.Entry) -> String {
        guard let value = entry.value else { return tr("Remove") }
        return entry.isUniform ? value.displayText : tr("Different values per file")
    }

    private func binding(for key: FieldKey) -> Binding<Bool> {
        Binding(
            get: { onlyWhereEmpty.contains(key) },
            set: { if $0 { onlyWhereEmpty.insert(key) } else { onlyWhereEmpty.remove(key) } }
        )
    }
}
