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
    private var prompt: Text? { field.isMixed ? Text(tr("Multiple values")).italic() : nil }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(field.label)
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
            Text(field.isMixed ? tr("Multiple values") : currentText)
                .textSelection(.enabled)
                .foregroundStyle(field.isMixed ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 3)
        } else {
            switch field.spec.kind {
            case .text:
                DraftTextField(value: currentText, prompt: prompt) { commitText($0) }
            case .integer:
                DraftTextField(value: currentText, prompt: prompt, isValid: Self.isWholeNumber) {
                    commitText($0.trimmingCharacters(in: .whitespaces))
                }
                .help(tr("Enter a whole number"))
            case .list:
                DraftTextField(value: currentText, prompt: prompt ?? Text(tr("Comma separated"))) { commitList($0) }
            case .lines:
                DraftTextEditor(value: linesText, placeholder: field.isMixed ? tr("Multiple values") : tr("One per line")) { commitLines($0) }
            case .multiline:
                DraftTextEditor(value: currentText, placeholder: field.isMixed ? tr("Multiple values") : "") { commitText($0) }
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
                Text(tr("Multiple values")).italic().foregroundStyle(.secondary)
            } else if field.displayValue == nil {
                Text(tr("Not set")).foregroundStyle(.tertiary)
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
            Button(field.isMixed ? tr("Set the same date for all") : tr("Set date")) {
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
                .help(tr("Revert this field"))
            }
            if field.isMixed, !field.mixedValues.isEmpty {
                Button { showValues.toggle() } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .help(tr("Values differ between the selected files"))
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
                .help(tr("Remove this field from all selected files"))
            }
            if field.supportCount < field.total {
                Text("\(field.supportCount)/\(field.total)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help(tr("Available in %d of %d selected files", field.supportCount, field.total))
            }
        }
        .padding(.top, 4)
    }

    private static func isWholeNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || Int(trimmed) != nil
    }

    /// Stages `value` for the selected files. An empty value removes the field, except where the files'
    /// values differ: clearing such a field goes back to "multiple values" instead of deleting it everywhere.
    private func commit(_ value: FieldValue) {
        if !value.isEmpty {
            state.stage(value, for: key, in: files)
        } else if case .mixed = field.original {
            state.revert(key, in: files)
        } else {
            state.stage(nil, for: key, in: files)
        }
    }

    private func commitText(_ text: String) { commit(.text(text)) }
    private func commitList(_ text: String) { commit(.list(Self.items(text.split(separator: ",")))) }
    private func commitLines(_ text: String) { commit(.list(Self.items(text.split(whereSeparator: \.isNewline)))) }

    private static func items(_ parts: [Substring]) -> [String] {
        parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var linesText: String {
        if case .list(let items)? = field.displayValue { return items.joined(separator: "\n") }
        return currentText
    }
}

/// Keeps a local draft while its control is focused, so normalisation of the model value never fights the cursor.
/// A draft that fails `isValid` is not passed on, and `content` is told so it can mark it; leaving the control
/// restores the value.
struct DraftEditing<Content: View>: View {
    let value: String
    var isValid: (String) -> Bool = { _ in true }
    let onChange: (String) -> Void
    @ViewBuilder let content: (_ draft: Binding<String>, _ isInvalid: Bool) -> Content
    @ViewState private var draft = ""
    @ViewState private var isInvalid = false
    @FocusState private var focused: Bool

    var body: some View {
        content($draft, isInvalid)
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { _, new in
                if !focused { draft = new }
            }
            .onChange(of: draft) { _, new in
                guard focused else { return }
                isInvalid = !isValid(new)
                if !isInvalid, new != value { onChange(new) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    draft = value
                    isInvalid = false
                }
            }
    }
}

struct DraftTextField: View {
    let value: String
    let prompt: Text?
    var isValid: (String) -> Bool = { _ in true }
    let onChange: (String) -> Void

    var body: some View {
        DraftEditing(value: value, isValid: isValid, onChange: onChange) { draft, isInvalid in
            TextField("", text: draft, prompt: prompt)
                .textFieldStyle(.roundedBorder)
                .overlay {
                    if isInvalid {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(.red)
                    }
                }
        }
    }
}

struct DraftTextEditor: View {
    let value: String
    let placeholder: String
    let onChange: (String) -> Void

    var body: some View {
        DraftEditing(value: value, onChange: onChange) { draft, _ in
            TextEditor(text: draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 72)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                .overlay(alignment: .topLeading) {
                    if draft.wrappedValue.isEmpty, !placeholder.isEmpty {
                        Text(placeholder)
                            .italic()
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 9)
                            .padding(.top, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

struct MixedValuesPopover: View {
    let values: [ValueCount]
    let onPick: (FieldValue?) -> Void

    /// Values listed before "and N more".
    private static let visibleCount = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Values in the selected files"))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(values.prefix(Self.visibleCount).enumerated()), id: \.offset) { _, entry in
                Button {
                    onPick(entry.value)
                } label: {
                    HStack {
                        Text(entry.value?.displayText ?? tr("(empty)"))
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
            if values.count > Self.visibleCount {
                Text(tr("and %d more", values.count - Self.visibleCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(tr("Click a value to use it for all selected files."))
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
    /// The decoded cover, updated when its bytes change rather than on every render.
    @ViewState private var image: NSImage?

    private var key: FieldKey { field.spec.key }

    private var coverData: Data? {
        if case .image(let data, _)? = field.displayValue { return data }
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
                return (try? load(url)) != nil
            } isTargeted: { isTargeted = $0 }

            VStack(alignment: .leading, spacing: 6) {
                Button(tr("Choose…")) { choose() }
                Button(tr("Remove")) { state.stage(nil, for: key, in: files) }
                    .disabled(!anyHasCover)
                Button(tr("Export…")) { export() }
                    .disabled(image == nil)
                if let image, let rep = image.representations.first {
                    Text("\(rep.pixelsWide) × \(rep.pixelsHigh)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if field.isMixed {
                    Text(tr("Covers differ"))
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
        }
        .onChange(of: coverData, initial: true) { _, data in
            image = data.flatMap(NSImage.init(data:))
        }
    }

    private func load(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        guard NSImage(data: data) != nil else {
            throw MetadataError(tr("%@ is not an image", url.lastPathComponent))
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? FieldValue.fallbackImageMIMEType
        state.stage(.image(data, mime: mime), for: key, in: files)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try load(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func export() {
        guard case .image(let data, let mime)? = field.displayValue else { return }
        let panel = NSSavePanel()
        // The panel adds the extension of the allowed type to the name.
        if let type = UTType(mimeType: mime) ?? UTType(mimeType: FieldValue.fallbackImageMIMEType) {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = files.first?.url.deletingPathExtension().lastPathComponent ?? ""
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
