import AppKit
import SwiftUI

struct FileListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        List(selection: $state.selection) {
            ForEach(state.filteredFiles) { file in
                FileRow(file: file)
                    .tag(file.id)
                    .contextMenu {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                        Button("Revert Changes") { file.revertAll() }.disabled(!file.isDirty)
                        Divider()
                        Button("Remove from List") { state.remove([file.id]) }
                    }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand { state.removeSelected() }
        .overlay {
            if state.files.isEmpty {
                ContentUnavailableView {
                    Label("No files", systemImage: "doc.badge.plus")
                } description: {
                    Text("Drop files or folders here, or press ⌘O.")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if state.isLoading || state.isSaving {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private var summary: String {
        if let status = state.status { return status }
        return "\(state.files.count) files, \(state.selection.count) selected"
    }
}

struct FileRow: View {
    let file: FileItem

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: file.icon)
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text((file.directory as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let error = file.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(error)
            }
            if file.isDirty {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
                    .help("Unsaved changes")
            }
        }
        .padding(.vertical, 2)
    }
}
