import CTagLib
import Foundation

/// Audio and MP4/Matroska tags through the TagLib C API. Uses TagLib's unified property map, so the
/// same keys work for ID3v2, Vorbis comments, MP4 atoms, APE, ASF and Matroska tags.
final class TagLibProvider: MetadataProvider {
    let id = "taglib"

    private static let extensions: Set<String> = [
        "mp3", "mp2", "flac", "ogg", "oga", "opus", "spx", "m4a", "m4b", "m4p", "m4r", "mp4", "m4v", "3g2", "3gp",
        "wav", "aif", "aiff", "aifc", "ape", "mpc", "wv", "tta", "wma", "asf", "dsf", "dff", "dsdiff", "shn",
        "mkv", "mka", "webm", "mod", "s3m", "it", "xm",
    ]

    private static let videoExtensions: Set<String> = ["mp4", "m4v", "3g2", "3gp", "mkv", "webm"]

    private static let pictureKey = "PICTURE"

    private enum Family { case id3, vorbis, mp4, ape, asf, matroska, other }

    private struct Mapping {
        let id: String
        let label: String
        let group: FieldGroup
        let kind: FieldKind
        let key: String
        /// Categories that get a non-General field. General fields follow GeneralField.fields(for:).
        var categories: Set<MediaCategory> = [.audio]
        /// Containers that have a place for the field; nil means all.
        var families: Set<Family>?

        init(id: String, label: String, group: FieldGroup, kind: FieldKind, key: String,
             categories: Set<MediaCategory> = [.audio], families: Set<Family>? = nil) {
            self.id = id
            self.label = label
            self.group = group
            self.kind = kind
            self.key = key
            self.categories = categories
            self.families = families
        }

        init(_ field: GeneralField, key: String) {
            self.init(id: field.rawValue, label: "", group: .general, kind: field.kind, key: key)
        }

        var generalField: GeneralField? { group == .general ? GeneralField(rawValue: id) : nil }

        func applies(to category: MediaCategory, _ family: Family) -> Bool {
            if let families, !families.contains(family) { return false }
            if let field = generalField { return GeneralField.fields(for: category).contains(field) }
            return categories.contains(category)
        }

        func label(for category: MediaCategory) -> String {
            generalField?.label(for: category) ?? label
        }
    }

    private static let mappings: [Mapping] = [
        Mapping(.title, key: "TITLE"),
        Mapping(.artist, key: "ARTIST"),
        Mapping(.album, key: "ALBUM"),
        Mapping(.albumArtist, key: "ALBUMARTIST"),
        Mapping(.date, key: "DATE"),
        Mapping(.genre, key: "GENRE"),
        Mapping(.track, key: "TRACKNUMBER"),
        Mapping(.disc, key: "DISCNUMBER"),
        Mapping(.composer, key: "COMPOSER"),
        Mapping(.comment, key: "COMMENT"),
        Mapping(.description, key: "DESCRIPTION"),
        Mapping(.keywords, key: "KEYWORDS"),
        Mapping(.copyright, key: "COPYRIGHT"),
        Mapping(id: "lyrics", label: "Lyrics", group: .audio, kind: .multiline, key: "LYRICS"),
        Mapping(id: "bpm", label: "BPM", group: .audio, kind: .integer, key: "BPM"),
        Mapping(id: "publisher", label: "Publisher", group: .audio, kind: .text, key: "LABEL"),
        Mapping(id: "isrc", label: "ISRC", group: .audio, kind: .text, key: "ISRC"),
        Mapping(id: "encodedBy", label: "Encoded by", group: .audio, kind: .text, key: "ENCODEDBY"),
        Mapping(id: "compilation", label: "Compilation", group: .audio, kind: .boolean, key: "COMPILATION"),
        Mapping(id: "grouping", label: "Grouping", group: .audio, kind: .text, key: "GROUPING"),
        Mapping(id: "show", label: "TV show", group: .video, kind: .text, key: "TVSHOW", categories: [.video], families: [.mp4]),
        Mapping(id: "season", label: "Season", group: .video, kind: .integer, key: "TVSEASON", categories: [.video], families: [.mp4]),
        Mapping(id: "episode", label: "Episode", group: .video, kind: .integer, key: "TVEPISODE", categories: [.video], families: [.mp4]),
        Mapping(id: "episodeId", label: "Episode ID", group: .video, kind: .text, key: "TVEPISODEID", categories: [.video], families: [.mp4]),
        Mapping(id: "network", label: "TV network", group: .video, kind: .text, key: "TVNETWORK", categories: [.video], families: [.mp4]),
    ]

    init() {
        taglib_set_strings_unicode(1)
        taglib_id3v2_set_default_text_encoding(TagLib_ID3v2_UTF8)
    }

    func supports(_ url: URL) -> Bool {
        Self.extensions.contains(url.pathExtension.lowercased())
    }

    private func family(of url: URL) -> Family {
        switch url.pathExtension.lowercased() {
        case "mp3", "mp2", "wav", "aif", "aiff", "aifc", "dsf", "dff", "dsdiff": return .id3
        case "flac", "ogg", "oga", "opus", "spx": return .vorbis
        case "m4a", "m4b", "m4p", "m4r", "mp4", "m4v", "3g2", "3gp": return .mp4
        case "ape", "mpc", "wv", "tta", "shn": return .ape
        case "wma", "asf": return .asf
        case "mkv", "mka", "webm": return .matroska
        default: return .other
        }
    }

    private func category(of url: URL) -> MediaCategory {
        Self.videoExtensions.contains(url.pathExtension.lowercased()) ? .video : .audio
    }

    private func propertyKey(_ mapping: Mapping, _ family: Family) -> String {
        if mapping.id == "publisher", family == .vorbis { return "ORGANIZATION" }
        // TagLib maps the MP4 "desc" atom to PODCASTDESC; it is the description iTunes and the TV app show.
        if mapping.id == "description", family == .mp4 { return "PODCASTDESC" }
        return mapping.key
    }

    private func key(_ id: String) -> FieldKey { FieldKey(provider: self.id, id: id) }

    private func key(for mapping: Mapping) -> FieldKey {
        mapping.group == .general ? FieldKey(provider: GeneralField.providerID, id: mapping.id) : key(mapping.id)
    }

    // MARK: Read

    func read(url: URL) throws -> ProviderData {
        guard let file = taglib_file_new(url.path) else {
            throw MetadataError(tr("TagLib could not open %@", url.lastPathComponent))
        }
        defer { taglib_file_free(file) }
        guard taglib_file_is_valid(file) != 0 else {
            throw MetadataError(tr("Unsupported or damaged media file"))
        }

        let family = family(of: url)
        let category = category(of: url)
        let props = readProperties(file)
        var data = ProviderData()
        var order = 0

        for mapping in Self.mappings where mapping.applies(to: category, family) {
            var values = props[propertyKey(mapping, family)] ?? []
            switch mapping.id {
            case "publisher" where values.isEmpty:
                values = props["ORGANIZATION"] ?? props["PUBLISHER"] ?? props["LABEL"] ?? []
            case "track":
                values = Self.withTotal(values, total: props["TRACKTOTAL"] ?? props["TOTALTRACKS"])
            case "disc":
                values = Self.withTotal(values, total: props["DISCTOTAL"] ?? props["TOTALDISCS"])
            default:
                break
            }
            let value: FieldValue?
            switch mapping.kind {
            case .list:
                value = values.isEmpty ? nil : .list(values)
            case .boolean:
                value = values.first.map { .bool($0 == "1" || $0.lowercased() == "true") }
            default:
                value = values.isEmpty ? nil : .text(values.joined(separator: "; "))
            }
            let specOrder = mapping.generalField?.order ?? order
            data.add(FieldSpec(key: key(for: mapping), label: mapping.label(for: category), group: mapping.group, kind: mapping.kind, order: specOrder), value)
            order += 1
        }

        if GeneralField.fields(for: category).contains(.cover) {
            data.add(GeneralField.cover.spec(for: category), readPicture(file))
        }

        if let properties = taglib_file_audioproperties(file) {
            let seconds = Int(taglib_audioproperties_length(properties))
            let technical: [(String, String, String)] = [
                ("duration", "Duration", String(format: "%d:%02d", seconds / 60, seconds % 60)),
                ("bitrate", "Bitrate", tr("%d kb/s", Int(taglib_audioproperties_bitrate(properties)))),
                ("sampleRate", "Sample rate", tr("%d Hz", Int(taglib_audioproperties_samplerate(properties)))),
                ("channels", "Channels", "\(taglib_audioproperties_channels(properties))"),
            ]
            for (id, label, text) in technical {
                data.add(FieldSpec(key: key(id), label: label, group: .technical, kind: .text, writable: false, order: order), .text(text))
                order += 1
            }
        }

        for rawKey in props.keys.sorted() {
            let values = props[rawKey] ?? []
            let kind: FieldKind = values.count > 1 ? .list : .text
            data.add(
                FieldSpec(key: key("raw:" + rawKey), label: rawKey, group: .raw, kind: kind, order: order),
                kind == .list ? .list(values) : values.first.map(FieldValue.text)
            )
            order += 1
        }
        return data
    }

    private static func withTotal(_ values: [String], total: [String]?) -> [String] {
        guard let first = values.first, let total = total?.first, !total.isEmpty, !first.contains("/") else { return values }
        return [first + "/" + total]
    }

    private func readProperties(_ file: UnsafeMutablePointer<TagLib_File>) -> [String: [String]] {
        var result: [String: [String]] = [:]
        guard let keys = taglib_property_keys(file) else { return result }
        defer { taglib_property_free(keys) }
        var i = 0
        while let rawKey = keys[i] {
            let name = String(cString: rawKey)
            if let values = taglib_property_get(file, rawKey) {
                var list: [String] = []
                var j = 0
                while let value = values[j] {
                    list.append(String(cString: value))
                    j += 1
                }
                taglib_property_free(values)
                result[name] = list
            }
            i += 1
        }
        return result
    }

    private func readPicture(_ file: UnsafeMutablePointer<TagLib_File>) -> FieldValue? {
        guard let properties = taglib_complex_property_get(file, Self.pictureKey) else { return nil }
        defer { taglib_complex_property_free(properties) }
        var picture = TagLib_Complex_Property_Picture_Data()
        taglib_picture_from_complex_property(properties, &picture)
        guard let bytes = picture.data, picture.size > 0 else { return nil }
        let data = Data(bytes: bytes, count: Int(picture.size))
        let mime = picture.mimeType.map { String(cString: $0) } ?? "image/jpeg"
        return .image(data, mime: mime)
    }

    // MARK: Write

    func write(url: URL, changes: [FieldKey: FieldValue?]) throws -> URL {
        guard let file = taglib_file_new(url.path) else {
            throw MetadataError(tr("TagLib could not open %@", url.lastPathComponent))
        }
        defer { taglib_file_free(file) }
        guard taglib_file_is_valid(file) != 0 else {
            throw MetadataError(tr("Unsupported or damaged media file"))
        }
        let family = family(of: url)

        for (fieldKey, entry) in changes {
            let value: FieldValue? = entry
            if fieldKey == GeneralField.cover.key {
                try setPicture(file, value)
                continue
            }
            if fieldKey.id.hasPrefix("raw:") {
                setProperty(file, String(fieldKey.id.dropFirst(4)), value?.strings)
                continue
            }
            guard let mapping = Self.mappings.first(where: { $0.id == fieldKey.id }) else { continue }
            let propertyKey = propertyKey(mapping, family)
            switch mapping.id {
            case "track", "disc":
                let totalKey = mapping.id == "track" ? "TRACKTOTAL" : "DISCTOTAL"
                let text = value?.displayText.trimmingCharacters(in: .whitespaces) ?? ""
                if family == .vorbis {
                    let parts = text.split(separator: "/", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    setProperty(file, propertyKey, parts.first.map { [$0] })
                    setProperty(file, totalKey, parts.count > 1 ? [parts[1]] : nil)
                } else {
                    setProperty(file, propertyKey, text.isEmpty ? nil : [text])
                }
            case "compilation":
                if case .bool(let flag)? = value {
                    setProperty(file, propertyKey, flag ? ["1"] : nil)
                } else {
                    setProperty(file, propertyKey, nil)
                }
            default:
                setProperty(file, propertyKey, value?.strings)
            }
        }

        guard taglib_file_save(file) != 0 else {
            throw MetadataError(tr("TagLib could not save %@", url.lastPathComponent))
        }
        return url
    }

    private func setProperty(_ file: UnsafeMutablePointer<TagLib_File>, _ key: String, _ values: [String]?) {
        let values = (values ?? []).filter { !$0.isEmpty }
        guard let first = values.first else {
            taglib_property_set(file, key, nil)
            return
        }
        taglib_property_set(file, key, first)
        for value in values.dropFirst() {
            taglib_property_set_append(file, key, value)
        }
    }

    typealias PictureAttributes = UnsafeMutablePointer<UnsafePointer<TagLib_Complex_Property_Attribute>?>

    /// Replaces the first embedded picture, the one shown as the cover, or removes it when `value` is nil.
    /// Other pictures (back cover, booklet pages) are kept.
    private func setPicture(_ file: UnsafeMutablePointer<TagLib_File>, _ value: FieldValue?) throws {
        let existing = taglib_complex_property_get(file, Self.pictureKey)
        defer { if let existing { taglib_complex_property_free(existing) } }
        let others = Self.pictures(in: existing).dropFirst()

        // TagLib copies the attributes on every call, so the existing list can be freed afterwards.
        var isFirst = true
        func store(_ picture: PictureAttributes) -> Bool {
            defer { isFirst = false }
            if isFirst { return taglib_complex_property_set(file, Self.pictureKey, picture) != 0 }
            return taglib_complex_property_set_append(file, Self.pictureKey, picture) != 0
        }

        var ok = true
        let cover: (data: Data, mime: String)?
        if case .image(let data, let mime)? = value, !data.isEmpty { cover = (data, mime) } else { cover = nil }
        if let cover {
            ok = Self.withPictureAttributes(data: cover.data, mime: cover.mime, body: store)
        }
        for picture in others where ok {
            ok = store(picture)
        }
        if ok, isFirst {
            ok = taglib_complex_property_set(file, Self.pictureKey, nil) != 0
        }
        guard ok else {
            throw MetadataError(cover == nil ? tr("Could not remove the cover") : tr("Could not set the cover"))
        }
    }

    /// Entries of a list returned by taglib_complex_property_get, typed for passing back to the setters.
    private static func pictures(
        in list: UnsafeMutablePointer<UnsafeMutablePointer<UnsafeMutablePointer<TagLib_Complex_Property_Attribute>?>?>?
    ) -> [PictureAttributes] {
        guard let list else { return [] }
        var result: [PictureAttributes] = []
        var index = 0
        while let entry = list[index] {
            result.append(UnsafeMutableRawPointer(entry).assumingMemoryBound(to: UnsafePointer<TagLib_Complex_Property_Attribute>?.self))
            index += 1
        }
        return result
    }

    /// Calls `body` with the attributes of a picture made from `data`, as TagLib's PICTURE setters take them.
    static func withPictureAttributes<Result>(
        data: Data, mime: String, type: String = "Front Cover", body: (PictureAttributes) -> Result
    ) -> Result {
        let bytes = UnsafeMutablePointer<CChar>.allocate(capacity: data.count)
        data.withUnsafeBytes { raw in
            _ = memcpy(bytes, raw.baseAddress!, data.count)
        }
        let keys = ["data", "mimeType", "description", "pictureType"].map { (name: String) in strdup(name)! }
        let strings = [strdup(mime)!, strdup("")!, strdup(type)!]
        defer {
            bytes.deallocate()
            keys.forEach { free($0) }
            strings.forEach { free($0) }
        }

        var attributes = [TagLib_Complex_Property_Attribute](repeating: TagLib_Complex_Property_Attribute(), count: keys.count)
        attributes[0].key = keys[0]
        attributes[0].value.type = TagLib_Variant_ByteVector
        attributes[0].value.size = UInt32(data.count)
        attributes[0].value.value.byteVectorValue = bytes
        for (index, string) in strings.enumerated() {
            attributes[index + 1].key = keys[index + 1]
            attributes[index + 1].value.type = TagLib_Variant_String
            attributes[index + 1].value.value.stringValue = string
        }
        return attributes.withUnsafeBufferPointer { buffer in
            var pointers: [UnsafePointer<TagLib_Complex_Property_Attribute>?] = buffer.indices.map { buffer.baseAddress! + $0 }
            pointers.append(nil)
            return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
        }
    }
}
