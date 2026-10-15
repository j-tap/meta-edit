import CTagLib
import Foundation

/// Audio and MP4/Matroska tags through the TagLib C API. Uses TagLib's unified property map, so the
/// same keys work for ID3v2, Vorbis comments, MP4 atoms, APE, ASF and Matroska tags.
struct TagLibProvider: MetadataProvider {
    let id = ProviderID.tagLib

    private static let pictureKey = "PICTURE"

    /// TagLib's C API settings are global, so they are applied once, before the first file is opened.
    private static let configureTagLib: Void = {
        taglib_set_strings_unicode(1)
        taglib_id3v2_set_default_text_encoding(TagLib_ID3v2_UTF8)
    }()

    // MARK: Formats

    private enum Family: Sendable { case id3, vorbis, mp4, ape, asf, matroska, other }

    private struct Format: Sendable {
        let family: Family
        let category: MediaCategory
    }

    /// Supported file extensions, with the tag family and what the editor treats them as.
    private static let formats: [String: Format] = {
        let groups: [(Family, MediaCategory, [String])] = [
            (.id3, .audio, ["mp3", "mp2", "wav", "aif", "aiff", "aifc", "dsf", "dff", "dsdiff"]),
            (.vorbis, .audio, ["flac", "ogg", "oga", "opus", "spx"]),
            (.mp4, .audio, ["m4a", "m4b", "m4p", "m4r"]),
            (.mp4, .video, ["mp4", "m4v", "3g2", "3gp"]),
            (.ape, .audio, ["ape", "mpc", "wv", "tta", "shn"]),
            (.asf, .audio, ["wma", "asf"]),
            (.matroska, .audio, ["mka"]),
            (.matroska, .video, ["mkv", "webm"]),
            (.other, .audio, ["mod", "s3m", "it", "xm"]),
        ]
        return Dictionary(uniqueKeysWithValues: groups.flatMap { family, category, extensions in
            extensions.map { ($0, Format(family: family, category: category)) }
        })
    }()

    private static func format(of url: URL) -> Format? {
        formats[url.pathExtension.lowercased()]
    }

    // MARK: Fields

    /// Where a field lives in TagLib's property map.
    private struct Mapping: Sendable {
        let field: any FieldDefinition
        let property: String
        /// Property used instead of `property` by some tag families.
        var propertyByFamily: [Family: String]
        /// Properties read, in order, when the file has no `property`.
        var fallbacks: [String]
        /// For "n/total" fields, the properties that may hold the total; the first one is written.
        var totals: [String]
        /// Categories that get a TagLib field. General fields follow GeneralField.fields(for:).
        var categories: Set<MediaCategory>
        /// Tag families that have a place for the field; nil means all.
        var families: Set<Family>?

        init(_ field: any FieldDefinition, _ property: String, propertyByFamily: [Family: String] = [:],
             fallbacks: [String] = [], totals: [String] = [], categories: Set<MediaCategory> = [.audio],
             families: Set<Family>? = nil) {
            self.field = field
            self.property = property
            self.propertyByFamily = propertyByFamily
            self.fallbacks = fallbacks
            self.totals = totals
            self.categories = categories
            self.families = families
        }

        func applies(to format: Format) -> Bool {
            if let families, !families.contains(format.family) { return false }
            if case .general(let general) = field.key { return GeneralField.fields(for: format.category).contains(general) }
            return categories.contains(format.category)
        }

        func property(for family: Family) -> String {
            propertyByFamily[family] ?? property
        }
    }

    private static let mappings: [Mapping] = [
        Mapping(GeneralField.title, "TITLE"),
        Mapping(GeneralField.artist, "ARTIST"),
        Mapping(GeneralField.album, "ALBUM"),
        Mapping(GeneralField.albumArtist, "ALBUMARTIST"),
        Mapping(GeneralField.date, "DATE"),
        Mapping(GeneralField.genre, "GENRE"),
        Mapping(GeneralField.track, "TRACKNUMBER", totals: ["TRACKTOTAL", "TOTALTRACKS"]),
        Mapping(GeneralField.disc, "DISCNUMBER", totals: ["DISCTOTAL", "TOTALDISCS"]),
        Mapping(GeneralField.composer, "COMPOSER"),
        Mapping(GeneralField.comment, "COMMENT"),
        // TagLib maps the MP4 "desc" atom to PODCASTDESC; it is the description iTunes and the TV app show.
        Mapping(GeneralField.description, "DESCRIPTION", propertyByFamily: [.mp4: "PODCASTDESC"]),
        Mapping(GeneralField.keywords, "KEYWORDS"),
        Mapping(GeneralField.copyright, "COPYRIGHT"),
        Mapping(TagLibField.lyrics, "LYRICS"),
        Mapping(TagLibField.bpm, "BPM"),
        Mapping(TagLibField.publisher, "LABEL", propertyByFamily: [.vorbis: "ORGANIZATION"],
                fallbacks: ["ORGANIZATION", "PUBLISHER", "LABEL"]),
        Mapping(TagLibField.isrc, "ISRC"),
        Mapping(TagLibField.encodedBy, "ENCODEDBY"),
        Mapping(TagLibField.compilation, "COMPILATION"),
        Mapping(TagLibField.grouping, "GROUPING"),
        Mapping(TagLibField.show, "TVSHOW", categories: [.video], families: [.mp4]),
        Mapping(TagLibField.season, "TVSEASON", categories: [.video], families: [.mp4]),
        Mapping(TagLibField.episode, "TVEPISODE", categories: [.video], families: [.mp4]),
        Mapping(TagLibField.episodeId, "TVEPISODEID", categories: [.video], families: [.mp4]),
        Mapping(TagLibField.network, "TVNETWORK", categories: [.video], families: [.mp4]),
    ]

    private static let mappingsByKey = Dictionary(uniqueKeysWithValues: mappings.map { ($0.field.key, $0) })

    func supports(_ url: URL) -> Bool {
        Self.format(of: url) != nil
    }

    /// Opens the file, checks that TagLib understands it and closes it after `body`.
    private static func withFile<Result>(_ url: URL, _ body: (UnsafeMutablePointer<TagLib_File>) throws -> Result) throws -> Result {
        _ = Self.configureTagLib
        guard let file = taglib_file_new(url.path) else {
            throw MetadataError(tr("TagLib could not open %@", url.lastPathComponent))
        }
        defer { taglib_file_free(file) }
        guard taglib_file_is_valid(file) != 0 else {
            throw MetadataError(tr("Unsupported or damaged media file"))
        }
        return try body(file)
    }

    // MARK: Read

    func read(url: URL) throws -> ProviderData {
        guard let format = Self.format(of: url) else {
            throw MetadataError(tr("Unsupported or damaged media file"))
        }
        return try Self.withFile(url) { file in
            let props = readProperties(file)
            var data = ProviderData()

            for mapping in Self.mappings where mapping.applies(to: format) {
                var values = props[mapping.property(for: format.family)] ?? []
                if values.isEmpty {
                    values = mapping.fallbacks.lazy.compactMap { props[$0] }.first ?? []
                }
                if !mapping.totals.isEmpty {
                    values = Self.withTotal(values, total: mapping.totals.lazy.compactMap { props[$0] }.first)
                }
                data.add(mapping.field.spec(for: format.category), FieldValue(strings: values, kind: mapping.field.kind))
            }

            if GeneralField.fields(for: format.category).contains(.cover) {
                let cover = Self.embeddedCover(file).map { Picture(bytes: $0.bytes, mimeType: $0.mimeType, source: .file(url)) }
                data.add(GeneralField.cover.spec(for: format.category), cover.map(FieldValue.picture))
            }

            if let properties = taglib_file_audioproperties(file) {
                let seconds = Int(taglib_audioproperties_length(properties))
                let technical: [(TagLibField, String)] = [
                    (.duration, String(format: "%d:%02d", seconds / 60, seconds % 60)),
                    (.bitrate, tr("%d kb/s", Int(taglib_audioproperties_bitrate(properties)))),
                    (.sampleRate, tr("%d Hz", Int(taglib_audioproperties_samplerate(properties)))),
                    (.channels, "\(taglib_audioproperties_channels(properties))"),
                ]
                for (field, text) in technical {
                    data.add(field.spec(), .text(text))
                }
            }

            for (order, name) in props.keys.sorted().enumerated() {
                let values = props[name] ?? []
                let kind: FieldKind = values.count > 1 ? .list : .text
                data.add(
                    .raw(.tagLibProperty(name), label: name, kind: kind, writable: true, order: order),
                    FieldValue(strings: values, kind: kind)
                )
            }
            return data
        }
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

    /// The bytes of the cover embedded in `url`, for a Picture that keeps only its digest.
    static func coverBytes(of url: URL) throws -> Data {
        let cover = try withFile(url) { embeddedCover($0) }
        guard let cover else {
            throw MetadataError(tr("The cover of %@ changed since it was loaded", url.lastPathComponent))
        }
        return cover.bytes
    }

    /// The first embedded picture, the one shown as the cover, with the MIME type its tag declares.
    private static func embeddedCover(_ file: UnsafeMutablePointer<TagLib_File>) -> (bytes: Data, mimeType: String?)? {
        guard let properties = taglib_complex_property_get(file, pictureKey) else { return nil }
        defer { taglib_complex_property_free(properties) }
        var picture = TagLib_Complex_Property_Picture_Data()
        taglib_picture_from_complex_property(properties, &picture)
        guard let bytes = picture.data, picture.size > 0 else { return nil }
        let mimeType = picture.mimeType.map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        return (Data(bytes: bytes, count: Int(picture.size)), mimeType)
    }

    // MARK: Write

    func write(url: URL, changes: [FieldKey: FieldValue?]) throws -> URL {
        guard let format = Self.format(of: url) else {
            throw MetadataError(tr("Unsupported or damaged media file"))
        }
        // A cover copied from another file is read before this one is opened for writing.
        let cover: (bytes: Data, mimeType: String)?
        if case .picture(let picture)?? = changes[.general(.cover)] {
            cover = (try picture.bytes(), picture.mimeType)
        } else {
            cover = nil
        }
        try Self.withFile(url) { file in
            for (key, value) in changes {
                switch key {
                case .general(.cover):
                    try setPicture(file, cover)
                case .tagLibProperty(let name):
                    setProperty(file, name, value?.strings)
                default:
                    guard let mapping = Self.mappingsByKey[key] else { continue }
                    write(value, for: mapping, family: format.family, to: file)
                }
            }
            guard taglib_file_save(file) != 0 else {
                throw MetadataError(tr("TagLib could not save %@", url.lastPathComponent))
            }
        }
        return url
    }

    private func write(_ value: FieldValue?, for mapping: Mapping, family: Family, to file: UnsafeMutablePointer<TagLib_File>) {
        let property = mapping.property(for: family)
        if let totalProperty = mapping.totals.first {
            // "n" or "n/total". Vorbis comments keep the total in a property of its own.
            let text = value?.displayText.trimmingCharacters(in: .whitespaces) ?? ""
            if family == .vorbis {
                let parts = text.split(separator: "/", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                setProperty(file, property, parts.first.map { [$0] })
                setProperty(file, totalProperty, parts.count > 1 ? [parts[1]] : nil)
            } else {
                setProperty(file, property, text.isEmpty ? nil : [text])
            }
        } else if mapping.field.kind == .boolean {
            // An unset flag is removed rather than written as "0".
            if case .bool(true)? = value {
                setProperty(file, property, ["1"])
            } else {
                setProperty(file, property, nil)
            }
        } else {
            setProperty(file, property, value?.strings)
        }
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

    /// Replaces the first embedded picture, the one shown as the cover, or removes it when `cover` is nil.
    /// Other pictures (back cover, booklet pages) are kept.
    private func setPicture(_ file: UnsafeMutablePointer<TagLib_File>, _ cover: (bytes: Data, mimeType: String)?) throws {
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
        if let cover, !cover.bytes.isEmpty {
            ok = Self.withPictureAttributes(data: cover.bytes, mime: cover.mimeType, body: store)
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
