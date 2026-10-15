import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FieldRow: View {
    @Environment(AppState.self) private var state
    let field: FieldState
    let files: [FileItem]
    @ViewState private var showValues = false

    private var key: FieldKey { field.spec.key }
    private var isEditable: Bool { field.spec.writable && files.allSatisfy(\.isWritable) }
    private var currentText: String { field.displayValue?.displayText ?? "" }
    private var prompt: Text? { field.isMixed ? Text("Multiple values").italic() : nil }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(field.spec.label)
                .frame(width: 130, alignment: .trailing)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
            control
                .frame(maxWidth: .infinity, alignment: .leading)
            indicators
                .frame(width: 84, alignment: .leading)
        }
    }

    @ViewBuilder
    private var control: some View {
        if !isEditable {
            Text(field.isMixed ? "Multiple values" : currentText)
                .textSelection(.enabled)
                .foregroundStyle(field.isMixed ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 3)
        } else {
            switch field.spec.kind {
            case .text, .integer:
                DraftTextField(value: currentText, prompt: prompt) { commitText($0) }
            case .list:
                DraftTextField(value: currentText, prompt: prompt ?? Text("Comma separated")) { commitList($0) }
            case .multiline:
                DraftTextEditor(value: currentText, placeholder: field.isMixed ? "Multiple values" : "") { commitText($0) }
            case .boolean:
                boolControl
            case .date:
                dateControl
            case .image:
                CoverField(field: field, files: files)
            }
        }
    }

    private var boolControl: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: {
                    if case .bool(let flag)? = field.displayValue { return flag }
                    return false
                },
                set: { state.stage(.bool($0), for: key, in: files) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            if field.isMixed {
                Text("Multiple values").italic().foregroundStyle(.secondary)
            } else if field.displayValue == nil {
                Text("Not set").foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 3)
    }

    @ViewBuilder
    private var dateControl: some View {
        if case .date(let date)? = field.displayValue {
            DatePicker(
                "",
                selection: Binding(get: { date }, set: { state.stage(.date($0), for: key, in: files) }),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
        } else {
            Button(field.isMixed ? "Set the same date for all" : "Set date") {
                state.stage(.date(Date()), for: key, in: files)
            }
        }
    }

    private var indicators: some View {
        HStack(spacing: 6) {
            if field.isPending {
                Button { state.revert(key, in: files) } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Revert this field")
            }
            if field.isMixed, !field.mixedValues.isEmpty {
                Button { showValues.toggle() } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .help("Values differ between the selected files")
                .popover(isPresented: $showValues) {
                    MixedValuesPopover(values: field.mixedValues) { chosen in
                        state.stage(chosen, for: key, in: files)
                        showValues = false
                    }
                }
            }
            if field.isMixed, isEditable, field.spec.kind != .image {
                Button { state.stage(nil, for: key, in: files) } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .help("Remove this field from all selected files")
            }
            if field.supportCount < field.total {
                Text("\(field.supportCount)/\(field.total)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("Available in \(field.supportCount) of \(field.total) selected files")
            }
        }
        .padding(.top, 4)
    }

    private func commitText(_ text: String) {
        if text.isEmpty {
            // Clearing a field whose values differ goes back to "multiple values" instead of deleting everywhere.
            if case .mixed = field.original {
                state.revert(key, in: files)
            } else {
                state.stage(nil, for: key, in: files)
            }
        } else {
            state.stage(.text(text), for: key, in: files)
        }
    }

    private func commitList(_ text: String) {
        let items = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if items.isEmpty {
            if case .mixed = field.original {
                state.revert(key, in: files)
            } else {
                state.stage(nil, for: key, in: files)
            }
        } else {
            state.stage(.list(items), for: key, in: files)
        }
    }
}

/// Text field that keeps a local draft while focused, so normalisation of the model value never fights the cursor.
struct DraftTextField: View {
    let value: String
    let prompt: Text?
    let onChange: (String) -> Void
    @ViewState private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft, prompt: prompt)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { _, new in
                if !focused { draft = new }
            }
            .onChange(of: draft) { _, new in
                if focused, new != value { onChange(new) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { draft = value }
            }
    }
}

struct DraftTextEditor: View {
    let value: String
    let placeholder: String
    let onChange: (String) -> Void
    @ViewState private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $draft)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(height: 72)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            .overlay(alignment: .topLeading) {
                if draft.isEmpty, !placeholder.isEmpty {
                    Text(placeholder)
                        .italic()
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 9)
                        .padding(.top, 5)
                        .allowsHitTesting(false)
                }
            }
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { _, new in
                if !focused { draft = new }
            }
            .onChange(of: draft) { _, new in
                if focused, new != value { onChange(new) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { draft = value }
            }
    }
}

struct MixedValuesPopover: View {
    let values: [ValueCount]
    let onPick: (FieldValue?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Values in the selected files")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(values.prefix(10).enumerated()), id: \.offset) { _, entry in
                Button {
                    onPick(entry.value)
                } label: {
                    HStack {
                        Text(entry.value?.displayText ?? "(empty)")
                            .lineLimit(1)
                            .foregroundStyle(entry.value == nil ? .secondary : .primary)
                        Spacer()
                        Text("\(entry.count)")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if values.count > 10 {
                Text("and \(values.count - 10) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Click a value to use it for all selected files.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(minWidth: 240, maxWidth: 380)
    }
}

struct CoverField: View {
    @Environment(AppState.self) private var state
    let field: FieldState
    let files: [FileItem]
    @ViewState private var isTargeted = false

    private var key: FieldKey { field.spec.key }

    private var image: NSImage? {
        if case .image(let data, _)? = field.displayValue { return NSImage(data: data) }
        return nil
    }

    private var anyHasCover: Bool {
        files.contains { file in
            if case .image? = file.currentValue(for: key) { return true }
            return false
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: field.isMixed ? "photo.stack" : "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 128, height: 128)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isTargeted ? Color.accentColor : .clear, lineWidth: 2))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return load(url)
            } isTargeted: { isTargeted = $0 }

            VStack(alignment: .leading, spacing: 6) {
                Button("Choose…") { choose() }
                Button("Remove") { state.stage(nil, for: key, in: files) }
                    .disabled(!anyHasCover)
                Button("Export…") { export() }
                    .disabled(image == nil)
                if let image, let rep = image.representations.first {
                    Text("\(rep.pixelsWide) × \(rep.pixelsHigh)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if field.isMixed {
                    Text("Covers differ")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
        }
    }

    private func load(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return false }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg"
        state.stage(.image(data, mime: mime), for: key, in: files)
        return true
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = load(url)
        }
    }

    private func export() {
        guard case .image(let data, let mime)? = field.displayValue else { return }
        let panel = NSSavePanel()
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "jpg"
        let base = files.first?.url.deletingPathExtension().lastPathComponent ?? "cover"
        panel.nameFieldStringValue = "\(base).\(ext)"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}
