import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(AppState.self) private var state
    @ViewState private var expanded: [FieldGroup: Bool] = [:]

    var body: some View {
        let files = state.selectedFiles
        if files.isEmpty {
            ContentUnavailableView {
                Label(state.files.isEmpty ? "No files" : "No selection", systemImage: "square.and.pencil")
            } description: {
                Text(state.files.isEmpty ? "Add files to get started." : "Select one or more files to edit their metadata.")
            }
        } else {
            let groups = SelectionFields.compute(files)
            VStack(spacing: 0) {
                EditorHeader(files: files)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(groups) { group in
                            FieldSectionView(group: group, files: files, isExpanded: binding(for: group.group))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func binding(for group: FieldGroup) -> Binding<Bool> {
        Binding(
            get: { expanded[group] ?? !group.isCollapsedByDefault },
            set: { expanded[group] = $0 }
        )
    }
}

struct EditorHeader: View {
    @Environment(AppState.self) private var state
    let files: [FileItem]

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: files.count == 1 ? files[0].icon : NSWorkspace.shared.icon(for: .data))
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(files.count == 1 ? files[0].name : "\(files.count) files")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(files.count == 1 ? (files[0].url.path as NSString).abbreviatingWithTildeInPath : files.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(files.map(\.name).joined(separator: "\n"))
            }
            Spacer()
            if !files.allSatisfy(\.isWritable) {
                Label("Read-only", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if files.contains(where: \.isDirty) {
                Text("Modified")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.2), in: Capsule())
                Button("Revert") { state.revert(files) }
            }
        }
        .padding(16)
    }
}

struct FieldSectionView: View {
    let group: FieldGroupState
    let files: [FileItem]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 8) {
                ForEach(group.fields) { field in
                    FieldRow(field: field, files: files)
                }
            }
            .padding(.top, 8)
        } label: {
            Text(group.group.title).font(.headline)
        }
    }
}
