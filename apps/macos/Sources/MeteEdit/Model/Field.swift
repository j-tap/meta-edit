import Foundation

/// Editor sections, in display order. See docs/metadata-schema.md.
enum FieldGroup: Int, CaseIterable, Comparable, Hashable {
    case general, audio, photo, video, document, file, technical, raw

    var title: String {
        switch self {
        case .general: return "General"
        case .audio: return "Audio"
        case .photo: return "Photo"
        case .video: return "Video"
        case .document: return "Document"
        case .file: return "File"
        case .technical: return "Technical"
        case .raw: return "All tags"
        }
    }

    var isCollapsedByDefault: Bool { self == .technical || self == .raw }

    static func < (lhs: FieldGroup, rhs: FieldGroup) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum FieldKind: Hashable {
    case text, multiline, integer, boolean, date, list, image
}

/// Identifies a field within a provider. Two providers may use the same id without clashing.
struct FieldKey: Hashable, Comparable, CustomStringConvertible {
    let provider: String
    let id: String

    var description: String { "\(provider).\(id)" }

    static func < (lhs: FieldKey, rhs: FieldKey) -> Bool {
        lhs.provider == rhs.provider ? lhs.id < rhs.id : lhs.provider < rhs.provider
    }
}

struct FieldSpec: Identifiable, Hashable {
    let key: FieldKey
    let label: String
    let group: FieldGroup
    let kind: FieldKind
    var writable: Bool = true
    var order: Int = 0

    var id: FieldKey { key }
}

enum FieldValue: Hashable {
    case text(String)
    case list([String])
    case bool(Bool)
    case date(Date)
    case image(Data, mime: String)

    var isEmpty: Bool {
        switch self {
        case .text(let s): return s.isEmpty
        case .list(let l): return l.isEmpty
        case .image(let d, _): return d.isEmpty
        case .bool, .date: return false
        }
    }

    var displayText: String {
        switch self {
        case .text(let s): return s
        case .list(let l): return l.joined(separator: ", ")
        case .bool(let b): return b ? "Yes" : "No"
        case .date(let d): return FieldValue.dateFormatter.string(from: d)
        case .image(let d, let mime):
            return "\(mime), \(ByteCountFormatter.string(fromByteCount: Int64(d.count), countStyle: .file))"
        }
    }

    /// String representation used when writing to tag containers.
    var strings: [String] {
        switch self {
        case .text(let s): return s.isEmpty ? [] : [s]
        case .list(let l): return l.filter { !$0.isEmpty }
        case .bool(let b): return [b ? "1" : "0"]
        case .date(let d): return [FieldValue.isoFormatter.string(from: d)]
        case .image: return []
        }
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static let isoFormatter = ISO8601DateFormatter()
}
