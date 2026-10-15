import Foundation

/// Editor sections, in display order. See docs/metadata-schema.md.
enum FieldGroup: Int, CaseIterable, Comparable, Hashable, Sendable {
    case general, audio, photo, video, document, file, technical, raw

    var title: String {
        switch self {
        case .general: return tr("General")
        case .audio: return tr("Audio")
        case .photo: return tr("Photo")
        case .video: return tr("Video")
        case .document: return tr("Document")
        case .file: return tr("File")
        case .technical: return tr("Technical")
        case .raw: return tr("All tags")
        }
    }

    var isCollapsedByDefault: Bool { self == .technical || self == .raw }

    static func < (lhs: FieldGroup, rhs: FieldGroup) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum FieldKind: Hashable, Sendable {
    /// `list` is edited as comma separated text, `lines` as one item per line (for items that may contain commas).
    case text, multiline, integer, boolean, date, list, lines, image
}

/// What a file is, as far as the editor is concerned. Decides which General fields a provider offers
/// and how they are labelled. See docs/metadata-schema.md.
enum MediaCategory: Hashable, CaseIterable, Sendable {
    case audio, video, image, other
}

/// The provider that reads and writes a field.
enum ProviderID: Hashable, Sendable {
    case tagLib, imageIO, file
}

/// Identifies a field. General fields are shared between providers, so an audio file and a photo edit
/// the same `.general(.title)`; the other named fields belong to one provider. Raw tags are any tag a
/// container holds, identified the way that container names it.
enum FieldKey: Hashable, Sendable {
    case general(GeneralField)
    case file(FileField)
    case tagLib(TagLibField)
    case image(ImageField)
    /// A key of TagLib's unified property map, such as `TITLE`.
    case tagLibProperty(String)
    /// An XMP property path, such as `xmpMM:DocumentID`.
    case xmp(String)
    /// An IPTC IIM dataset as ImageIO names it, such as `Keywords`. Read only.
    case iptc(String)
}

/// A named field: one case of GeneralField, FileField, TagLibField or ImageField.
protocol FieldDefinition: Hashable, Sendable {
    var key: FieldKey { get }
    var group: FieldGroup { get }
    var kind: FieldKind { get }
    /// Position within the group.
    var order: Int { get }
    /// English label; FieldSpec.displayLabel translates it. General fields are labelled per category.
    func label(for category: MediaCategory) -> String
}

extension FieldDefinition where Self: CaseIterable, AllCases == [Self] {
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

extension FieldDefinition {
    /// Technical fields are always read only.
    func spec(for category: MediaCategory = .other, writable: Bool = true) -> FieldSpec {
        FieldSpec(key: key, label: label(for: category), group: group, kind: kind, writable: writable && group != .technical, order: order)
    }
}

struct FieldSpec: Identifiable, Hashable, Sendable {
    let key: FieldKey
    /// English label, translated for display. Labels of raw tags are tag names and stay as they are.
    let label: String
    let group: FieldGroup
    let kind: FieldKind
    var writable: Bool = true
    var order: Int = 0

    var id: FieldKey { key }

    var displayLabel: String { group == .raw ? label : tr(label) }

    /// A raw tag, labelled with its own name.
    static func raw(_ key: FieldKey, label: String, kind: FieldKind, writable: Bool, order: Int) -> FieldSpec {
        FieldSpec(key: key, label: label, group: .raw, kind: kind, writable: writable, order: order)
    }
}

enum FieldValue: Hashable, Sendable {
    case text(String)
    case list([String])
    case bool(Bool)
    case date(Date)
    case picture(Picture)

    /// Joins the values of a multi-valued tag shown in a single-value field.
    static let separator = "; "

    /// MIME type assumed for a picture that does not say what it is: JPEG, which nearly every tagger writes.
    static let fallbackImageMIMEType = "image/jpeg"

    /// A value read from a tag container as strings: a list for list fields, a flag for boolean ones,
    /// otherwise the strings joined. Nil when there are none.
    init?(strings: [String], kind: FieldKind) {
        let strings = strings.filter { !$0.isEmpty }
        guard let first = strings.first else { return nil }
        switch kind {
        case .list, .lines: self = .list(strings)
        case .boolean: self = .bool(first == "1" || first.lowercased() == "true")
        default: self = .text(strings.joined(separator: Self.separator))
        }
    }

    var isEmpty: Bool {
        switch self {
        case .text(let s): return s.isEmpty
        case .list(let l): return l.isEmpty
        case .picture(let picture): return picture.byteCount == 0
        case .bool, .date: return false
        }
    }

    var displayText: String {
        switch self {
        case .text(let s): return s
        case .list(let l): return l.joined(separator: ", ")
        case .bool(let b): return b ? tr("Yes") : tr("No")
        case .date(let d): return d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localizer.shared.locale))
        case .picture(let picture):
            return "\(picture.mimeType), \(ByteCountFormatter.string(fromByteCount: Int64(picture.byteCount), countStyle: .file))"
        }
    }

    /// String representation used when writing to tag containers.
    var strings: [String] {
        switch self {
        case .text(let s): return s.isEmpty ? [] : [s]
        case .list(let l): return l.filter { !$0.isEmpty }
        case .bool(let b): return [b ? "1" : "0"]
        case .date(let d): return [d.formatted(.iso8601)]
        case .picture: return []
        }
    }
}
