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
            Text("Change \(request.files.count) files?")
                .font(.title2.weight(.semibold))
            Text("These fields will be written. Everything else in the files stays untouched.")
                .foregroundStyle(.secondary)
            List(entries) { entry in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.spec.label).fontWeight(.medium)
                        Text(description(for: entry))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text("\(entry.count) file\(entry.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    if entry.value != nil {
                        Toggle("Only where empty", isOn: binding(for: entry.spec.key))
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .help("Skip files that already have a value in this field")
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 140, maxHeight: 280)
            DisclosureGroup("Files", isExpanded: $showFiles) {
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
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Change \(request.files.count) files") {
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
        guard let value = entry.value else { return "Remove" }
        return entry.isUniform ? value.displayText : "Different values per file"
    }

    private func binding(for key: FieldKey) -> Binding<Bool> {
        Binding(
            get: { onlyWhereEmpty.contains(key) },
            set: { if $0 { onlyWhereEmpty.insert(key) } else { onlyWhereEmpty.remove(key) } }
        )
    }
}
