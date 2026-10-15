import Foundation

/// Fields of the General group are shared between providers: an audio file and a photo both expose
/// `general.title`, so a mixed selection edits one row. Display order follows this list.
/// Which of them a file gets, and how they are labelled, depends on its category.
/// See docs/metadata-schema.md.
enum GeneralField: String, CaseIterable {
    case title, artist, album, albumArtist, date, genre, track, disc, composer
    case comment, description, keywords, copyright, rating, cover

    static let providerID = "general"

    /// General fields offered per category, in the "Fields per file type" table of the schema.
    static func fields(for category: MediaCategory) -> Set<GeneralField> {
        switch category {
        case .audio:
            return [.title, .artist, .album, .albumArtist, .date, .genre, .track, .disc, .composer, .comment, .copyright, .cover]
        case .video:
            return [.title, .artist, .date, .genre, .comment, .description, .copyright, .cover]
        case .image:
            return [.title, .artist, .date, .description, .keywords, .copyright, .rating]
        case .other:
            return []
        }
    }

    var key: FieldKey { FieldKey(provider: Self.providerID, id: rawValue) }

    /// English label; FieldSpec.displayLabel translates it.
    func label(for category: MediaCategory) -> String {
        switch self {
        case .title: return "Title"
        case .artist: return category == .audio ? "Artist" : "Author"
        case .album: return "Album"
        case .albumArtist: return "Album artist"
        case .date:
            switch category {
            case .audio: return "Year"
            case .image: return "Date created"
            default: return "Date"
            }
        case .genre: return "Genre"
        case .track: return "Track"
        case .disc: return "Disc"
        case .composer: return "Composer"
        case .comment: return "Comment"
        case .description: return "Description"
        case .keywords: return "Keywords"
        case .copyright: return "Copyright"
        case .rating: return "Rating"
        case .cover: return "Cover"
        }
    }

    var kind: FieldKind {
        switch self {
        case .comment, .description: return .multiline
        case .keywords: return .list
        case .rating: return .integer
        case .cover: return .image
        default: return .text
        }
    }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    func spec(for category: MediaCategory, writable: Bool = true) -> FieldSpec {
        FieldSpec(key: key, label: label(for: category), group: .general, kind: kind, writable: writable, order: order)
    }
}
