import Foundation

/// Fields of the General group are shared between providers: an audio file and a photo both expose
/// `general.title`, so a mixed selection edits one row. Display order follows this list.
/// See docs/metadata-schema.md.
enum GeneralField: String, CaseIterable {
    case title, artist, album, albumArtist, date, genre, track, disc, composer
    case comment, description, keywords, copyright, rating, cover

    static let providerID = "general"

    var key: FieldKey { FieldKey(provider: Self.providerID, id: rawValue) }

    var label: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .albumArtist: return "Album artist"
        case .date: return "Date"
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

    func spec(writable: Bool = true) -> FieldSpec {
        FieldSpec(key: key, label: label, group: .general, kind: kind, writable: writable, order: order)
    }
}
