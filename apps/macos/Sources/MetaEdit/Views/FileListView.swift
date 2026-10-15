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
                        Button(tr("Reveal in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                        Button(tr("Revert Changes")) { file.revertAll() }.disabled(!file.isDirty)
                        Divider()
                        Button(tr("Remove from List")) { state.remove([file.id]) }
                    }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand { state.removeSelected() }
        .overlay {
            if state.files.isEmpty {
                ContentUnavailableView {
                    Label(tr("No files"), systemImage: "doc.badge.plus")
                } description: {
                    Text(tr("Drop files or folders here, or press ⌘O."))
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
        return tr("%@, %d selected", trPlural("%d files", state.files.count), state.selection.count)
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
                    .help(tr("Unsaved changes"))
            }
        }
        .padding(.vertical, 2)
    }
}
