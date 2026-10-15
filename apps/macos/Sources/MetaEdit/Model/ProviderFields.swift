import Foundation

// Named fields that belong to one provider. Display order within a group follows case order.
// See docs/metadata-schema.md.

/// Filesystem attributes, available for every file.
enum FileField: CaseIterable, FieldDefinition {
    case name, tags, comment, whereFrom, created, modified
    case folder, size, contentType

    var key: FieldKey { .file(self) }

    var group: FieldGroup {
        switch self {
        case .folder, .size, .contentType: .technical
        default: .file
        }
    }

    var kind: FieldKind {
        switch self {
        case .tags: .list
        case .comment: .multiline
        case .whereFrom: .lines
        case .created, .modified: .date
        default: .text
        }
    }

    func label(for _: MediaCategory) -> String {
        switch self {
        case .name: "Name"
        case .tags: "Tags"
        case .comment: "Comment"
        case .whereFrom: "Where from"
        case .created: "Created"
        case .modified: "Modified"
        case .folder: "Folder"
        case .size: "Size"
        case .contentType: "Kind"
        }
    }
}

/// Audio and video tags beyond the General ones, plus audio properties.
enum TagLibField: CaseIterable, FieldDefinition {
    case lyrics, bpm, publisher, isrc, encodedBy, compilation, grouping
    case show, season, episode, episodeId, network
    case duration, bitrate, sampleRate, channels

    var key: FieldKey { .tagLib(self) }

    var group: FieldGroup {
        switch self {
        case .show, .season, .episode, .episodeId, .network: .video
        case .duration, .bitrate, .sampleRate, .channels: .technical
        default: .audio
        }
    }

    var kind: FieldKind {
        switch self {
        case .lyrics: .multiline
        case .bpm, .season, .episode: .integer
        case .compilation: .boolean
        default: .text
        }
    }

    func label(for _: MediaCategory) -> String {
        switch self {
        case .lyrics: "Lyrics"
        case .bpm: "BPM"
        case .publisher: "Publisher"
        case .isrc: "ISRC"
        case .encodedBy: "Encoded by"
        case .compilation: "Compilation"
        case .grouping: "Grouping"
        case .show: "TV show"
        case .season: "Season"
        case .episode: "Episode"
        case .episodeId: "Episode ID"
        case .network: "TV network"
        case .duration: "Duration"
        case .bitrate: "Bitrate"
        case .sampleRate: "Sample rate"
        case .channels: "Channels"
        }
    }
}

/// Photo metadata beyond the General fields, plus image properties.
enum ImageField: CaseIterable, FieldDefinition {
    case headline, credit, source, city, state, country, colorLabel, software, userComment
    case dimensions, resolution, colorModel, colorProfile, orientation, camera, lens, exposure, gps

    var key: FieldKey { .image(self) }

    var group: FieldGroup {
        switch self {
        case .dimensions, .resolution, .colorModel, .colorProfile, .orientation, .camera, .lens, .exposure, .gps: .technical
        default: .photo
        }
    }

    var kind: FieldKind { self == .userComment ? .multiline : .text }

    func label(for _: MediaCategory) -> String {
        switch self {
        case .headline: "Headline"
        case .credit: "Credit"
        case .source: "Source"
        case .city: "City"
        case .state: "State"
        case .country: "Country"
        case .colorLabel: "Label"
        case .software: "Software"
        case .userComment: "User comment"
        case .dimensions: "Dimensions"
        case .resolution: "Resolution"
        case .colorModel: "Color"
        case .colorProfile: "Color profile"
        case .orientation: "Orientation"
        case .camera: "Camera"
        case .lens: "Lens"
        case .exposure: "Exposure"
        case .gps: "GPS"
        }
    }
}
