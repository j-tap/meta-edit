import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image metadata (XMP, Exif, IPTC) through ImageIO. Writing copies the image data losslessly and
/// replaces only the metadata segments; the pixels are never re-encoded.
///
/// Two ImageIO quirks are handled here: an XMP packet is only serialised when the `iio:hasXMP`
/// marker tag is present, and the IPTC IIM block is regenerated from XMP on write, so IPTC-only
/// values are mirrored into XMP before writing to keep them.
struct ImageIOProvider: MetadataProvider {
    let id = ProviderID.imageIO

    private static let readableTypes = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
    private static let writableTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    // Core Foundation strings are not Sendable, so the static tables below hold Swift strings.
    private static let iioNamespace = "http://ns.apple.com/ImageIO/1.0/"

    private static let namespaces: [String: String] = [
        "dc": kCGImageMetadataNamespaceDublinCore as String,
        "xmp": kCGImageMetadataNamespaceXMPBasic as String,
        "xmpRights": kCGImageMetadataNamespaceXMPRights as String,
        "photoshop": kCGImageMetadataNamespacePhotoshop as String,
        "exif": kCGImageMetadataNamespaceExif as String,
        "exifEX": kCGImageMetadataNamespaceExifEX as String,
        "aux": kCGImageMetadataNamespaceExifAux as String,
        "tiff": kCGImageMetadataNamespaceTIFF as String,
        "Iptc4xmpCore": kCGImageMetadataNamespaceIPTCCore as String,
    ]

    private enum XMPShape: Sendable { case text, langAlt, seq, bag }

    /// A value in one of ImageIO's property dictionaries, such as the IPTC object name.
    private struct PropertyPath: Sendable {
        let dictionary: String
        let key: String

        func strings(in properties: [CFString: Any]) -> [String] {
            guard let values = properties[dictionary as CFString] as? [CFString: Any] else { return [] }
            return ImageIOProvider.strings(from: values[key as CFString] as CFTypeRef?)
        }
    }

    /// Where a field lives: an XMP path, read with an Exif or IPTC fallback.
    private struct Mapping: Sendable {
        let field: any FieldDefinition
        let path: String
        let shape: XMPShape
        let fallback: PropertyPath?

        init(_ field: any FieldDefinition, path: String, shape: XMPShape, fallback: (dictionary: CFString, key: CFString)?) {
            self.field = field
            self.path = path
            self.shape = shape
            self.fallback = fallback.map { PropertyPath(dictionary: $0.dictionary as String, key: $0.key as String) }
        }
    }

    private static let mappings: [Mapping] = [
        Mapping(GeneralField.title, path: "dc:title", shape: .langAlt,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCObjectName)),
        Mapping(GeneralField.artist, path: "dc:creator", shape: .seq,
                fallback: (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFArtist)),
        Mapping(GeneralField.description, path: "dc:description", shape: .langAlt,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCCaptionAbstract)),
        Mapping(GeneralField.keywords, path: "dc:subject", shape: .bag,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCKeywords)),
        Mapping(GeneralField.copyright, path: "dc:rights", shape: .langAlt,
                fallback: (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFCopyright)),
        Mapping(GeneralField.date, path: "photoshop:DateCreated", shape: .text,
                fallback: (kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeOriginal)),
        Mapping(GeneralField.rating, path: "xmp:Rating", shape: .text, fallback: nil),
        Mapping(ImageField.headline, path: "photoshop:Headline", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCHeadline)),
        Mapping(ImageField.credit, path: "photoshop:Credit", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCCredit)),
        Mapping(ImageField.source, path: "photoshop:Source", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCSource)),
        Mapping(ImageField.city, path: "photoshop:City", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCCity)),
        Mapping(ImageField.state, path: "photoshop:State", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCProvinceState)),
        Mapping(ImageField.country, path: "photoshop:Country", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCCountryPrimaryLocationName)),
        Mapping(ImageField.colorLabel, path: "xmp:Label", shape: .text, fallback: nil),
        Mapping(ImageField.software, path: "xmp:CreatorTool", shape: .text,
                fallback: (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFSoftware)),
        Mapping(ImageField.userComment, path: "exif:UserComment", shape: .text,
                fallback: (kCGImagePropertyExifDictionary, kCGImagePropertyExifUserComment)),
    ]

    private static let mappingsByKey = Dictionary(uniqueKeysWithValues: mappings.map { ($0.field.key, $0) })

    func supports(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else { return false }
        return Self.readableTypes.contains(type.identifier)
    }

    // MARK: Read

    func read(url: URL) throws -> ProviderData {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw MetadataError(tr("ImageIO could not open %@", url.lastPathComponent))
        }
        let type = CGImageSourceGetType(source).map { $0 as String } ?? ""
        let writable = Self.writableTypes.contains(type)
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        var data = ProviderData()
        for mapping in Self.mappings {
            let strings = Self.currentStrings(for: mapping, metadata: metadata, properties: properties)
            data.add(mapping.field.spec(for: .image, writable: writable), FieldValue(strings: strings, kind: mapping.field.kind))
        }

        for (field, text) in Self.technical(properties) {
            data.add(field.spec(), .text(text))
        }

        // Raw tags keep the order they are added in: XMP by path, then IPTC by name.
        if let metadata {
            var tags: [(path: String, strings: [String], kind: FieldKind)] = []
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                let path = path as String
                guard !path.hasPrefix("iio:") else { return true }
                let strings = Self.strings(from: CGImageMetadataTagCopyValue(tag))
                guard !strings.isEmpty else { return true }
                switch CGImageMetadataTagGetType(tag) {
                case .string, .default, .alternateText:
                    tags.append((path, strings, .text))
                case .arrayOrdered, .arrayUnordered, .alternateArray:
                    tags.append((path, strings, .list))
                default:
                    break
                }
                return true
            }
            for tag in tags.sorted(by: { $0.path < $1.path }) {
                data.add(.raw(.xmp(tag.path), label: tag.path, kind: tag.kind, writable: writable, order: data.specs.count),
                         FieldValue(strings: tag.strings, kind: tag.kind))
            }
        }
        if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            for (name, value) in iptc.sorted(by: { ($0.key as String) < ($1.key as String) }) {
                let strings = Self.strings(from: value as CFTypeRef?)
                guard !strings.isEmpty else { continue }
                let kind: FieldKind = strings.count > 1 ? .list : .text
                data.add(.raw(.iptc(name as String), label: "IPTC " + (name as String), kind: kind, writable: false, order: data.specs.count),
                         FieldValue(strings: strings, kind: kind))
            }
        }
        return data
    }

    /// XMP value first, then the Exif / IPTC fallback.
    private static func currentStrings(for mapping: Mapping, metadata: CGImageMetadata?, properties: [CFString: Any]) -> [String] {
        if let metadata, let tag = CGImageMetadataCopyTagWithPath(metadata, nil, mapping.path as CFString) {
            let strings = strings(from: CGImageMetadataTagCopyValue(tag))
            if !strings.isEmpty { return strings }
        }
        return mapping.fallback?.strings(in: properties) ?? []
    }

    private static func strings(from value: CFTypeRef?) -> [String] {
        guard let value else { return [] }
        switch CFGetTypeID(value) {
        case CFStringGetTypeID():
            let string = value as! String
            return string.isEmpty ? [] : [string]
        case CFNumberGetTypeID():
            return [(value as! NSNumber).stringValue]
        case CFBooleanGetTypeID():
            return [(value as! Bool) ? "True" : "False"]
        case CFArrayGetTypeID():
            return (value as! [Any]).flatMap { strings(from: $0 as CFTypeRef) }
        case CFDictionaryGetTypeID():
            return (value as! [String: Any]).sorted { $0.key < $1.key }.flatMap { strings(from: $0.value as CFTypeRef) }
        case CGImageMetadataTagGetTypeID():
            return strings(from: CGImageMetadataTagCopyValue(value as! CGImageMetadataTag))
        default:
            return []
        }
    }

    private static func technical(_ properties: [CFString: Any]) -> [(ImageField, String)] {
        var result: [(ImageField, String)] = []
        if let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            result.append((.dimensions, "\(width) × \(height)"))
        }
        if let dpi = properties[kCGImagePropertyDPIWidth] as? Double, dpi > 0 {
            result.append((.resolution, "\(Int(dpi.rounded())) dpi"))
        }
        if let model = properties[kCGImagePropertyColorModel] as? String {
            let depth = (properties[kCGImagePropertyDepth] as? Int).map { " \($0)-bit" } ?? ""
            result.append((.colorModel, model + depth))
        }
        if let profile = properties[kCGImagePropertyProfileName] as? String {
            result.append((.colorProfile, profile))
        }
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation != 1 {
            result.append((.orientation, "\(orientation)"))
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let make = tiff[kCGImagePropertyTIFFMake] as? String ?? ""
        let model = tiff[kCGImagePropertyTIFFModel] as? String ?? ""
        if !make.isEmpty || !model.isEmpty {
            let camera = model.hasPrefix(make) ? model : [make, model].filter { !$0.isEmpty }.joined(separator: " ")
            result.append((.camera, camera))
        }
        if let lens = exif[kCGImagePropertyExifLensModel] as? String, !lens.isEmpty {
            result.append((.lens, lens))
        }
        var exposure: [String] = []
        if let time = exif[kCGImagePropertyExifExposureTime] as? Double, time > 0 {
            exposure.append(time >= 1 ? String(format: "%g s", time) : "1/\(Int((1 / time).rounded())) s")
        }
        if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double, fNumber > 0 {
            exposure.append(String(format: "f/%g", fNumber))
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first {
            exposure.append("ISO \(iso)")
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double, focal > 0 {
            exposure.append(String(format: "%g mm", focal))
        }
        if !exposure.isEmpty {
            result.append((.exposure, exposure.joined(separator: ", ")))
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
           let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latitudeSign = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -1.0 : 1.0
            let longitudeSign = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -1.0 : 1.0
            result.append((.gps, String(format: "%.5f, %.5f", latitude * latitudeSign, longitude * longitudeSign)))
        }
        return result
    }

    // MARK: Write

    func write(url: URL, changes: [FieldKey: FieldValue?]) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) else {
            throw MetadataError(tr("ImageIO could not open %@", url.lastPathComponent))
        }
        guard Self.writableTypes.contains(type as String) else {
            throw MetadataError(tr("ImageIO cannot write %@ files", url.pathExtension.uppercased()))
        }
        let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        guard let metadata = existing.map({ CGImageMetadataCreateMutableCopy($0) }) ?? CGImageMetadataCreateMutable() else {
            throw MetadataError(tr("Could not prepare metadata"))
        }
        var error: Unmanaged<CFError>?
        for (prefix, namespace) in Self.namespaces {
            _ = CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace as CFString, prefix as CFString, &error)
            error = nil
        }
        if CGImageMetadataCopyTagWithPath(metadata, nil, "iio:hasXMP" as CFString) == nil {
            _ = CGImageMetadataRegisterNamespaceForPrefix(metadata, Self.iioNamespace as CFString, "iio" as CFString, &error)
            error = nil
            _ = CGImageMetadataSetValueWithPath(metadata, nil, "iio:hasXMP" as CFString, kCFBooleanTrue)
        }

        // Keep IPTC-only values: ImageIO rebuilds the IPTC block from XMP, so mirror them into XMP first.
        for mapping in Self.mappings where mapping.fallback?.dictionary == kCGImagePropertyIPTCDictionary as String {
            let hasXMP = existing.flatMap { CGImageMetadataCopyTagWithPath($0, nil, mapping.path as CFString) } != nil
            guard !hasXMP, let strings = mapping.fallback?.strings(in: properties), !strings.isEmpty else { continue }
            try apply(FieldValue(strings: strings, kind: mapping.field.kind), path: mapping.path, shape: mapping.shape, to: metadata)
        }

        for (key, value) in changes {
            if case .xmp(let path) = key {
                let fallbackShape: XMPShape
                if case .list? = value { fallbackShape = .seq } else { fallbackShape = .text }
                let shape = Self.shape(ofExisting: path, in: existing) ?? fallbackShape
                try apply(value, path: path, shape: shape, to: metadata)
            } else if let mapping = Self.mappingsByKey[key] {
                try apply(value, path: mapping.path, shape: mapping.shape, to: metadata)
            }
        }

        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).metaedit-\(UUID().uuidString.prefix(8))")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, 1, nil) else {
            throw MetadataError(tr("Could not create %@", temporary.lastPathComponent))
        }
        let options: [CFString: Any] = [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: false]
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
            try? FileManager.default.removeItem(at: temporary)
            let reason = error?.takeRetainedValue().localizedDescription ?? tr("unknown error")
            throw MetadataError(tr("ImageIO could not write %@: %@", url.lastPathComponent, reason))
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return url
    }

    private static func shape(ofExisting path: String, in metadata: CGImageMetadata?) -> XMPShape? {
        guard let metadata, let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) else { return nil }
        switch CGImageMetadataTagGetType(tag) {
        case .alternateText: return .langAlt
        case .arrayOrdered: return .seq
        case .arrayUnordered, .alternateArray: return .bag
        default: return .text
        }
    }

    private func apply(_ value: FieldValue?, path: String, shape: XMPShape, to metadata: CGMutableImageMetadata) throws {
        let strings = value?.strings ?? []
        guard !strings.isEmpty else {
            _ = CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
            return
        }
        let ok: Bool
        switch shape {
        case .text:
            ok = CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, strings.joined(separator: FieldValue.separator) as CFString)
        case .langAlt:
            _ = CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
            ok = CGImageMetadataSetValueWithPath(metadata, nil, "\(path)[x-default]" as CFString, strings.joined(separator: FieldValue.separator) as CFString)
        case .seq, .bag:
            let parts = path.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let namespace = Self.namespaces[parts[0]] else {
                throw MetadataError(tr("Unknown XMP namespace in %@", path))
            }
            let tagType: CGImageMetadataType = shape == .seq ? .arrayOrdered : .arrayUnordered
            guard let tag = CGImageMetadataTagCreate(namespace as CFString, parts[0] as CFString, parts[1] as CFString, tagType, strings as CFArray) else {
                throw MetadataError(tr("Could not create tag %@", path))
            }
            ok = CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag)
        }
        guard ok else { throw MetadataError(tr("Could not set %@", path)) }
    }
}
