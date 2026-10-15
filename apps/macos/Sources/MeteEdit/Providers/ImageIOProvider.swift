import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image metadata (XMP, Exif, IPTC) through ImageIO. Writing copies the image data losslessly and
/// replaces only the metadata segments; the pixels are never re-encoded.
///
/// Two ImageIO quirks are handled here: an XMP packet is only serialised when the `iio:hasXMP`
/// marker tag is present, and the IPTC IIM block is regenerated from XMP on write, so IPTC-only
/// values are mirrored into XMP before writing to keep them.
final class ImageIOProvider: MetadataProvider {
    let id = "imageio"

    private static let readableTypes = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
    private static let writableTypes = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    private static let iioNamespace = "http://ns.apple.com/ImageIO/1.0/" as CFString

    private static let namespaces: [String: CFString] = [
        "dc": kCGImageMetadataNamespaceDublinCore,
        "xmp": kCGImageMetadataNamespaceXMPBasic,
        "xmpRights": kCGImageMetadataNamespaceXMPRights,
        "photoshop": kCGImageMetadataNamespacePhotoshop,
        "exif": kCGImageMetadataNamespaceExif,
        "exifEX": kCGImageMetadataNamespaceExifEX,
        "aux": kCGImageMetadataNamespaceExifAux,
        "tiff": kCGImageMetadataNamespaceTIFF,
        "Iptc4xmpCore": kCGImageMetadataNamespaceIPTCCore,
    ]

    private enum XMPShape { case text, langAlt, seq, bag }

    private struct Mapping {
        let id: String
        let label: String
        let group: FieldGroup
        let kind: FieldKind
        let path: String
        let shape: XMPShape
        let fallback: (dictionary: CFString, key: CFString)?

        init(id: String, label: String, group: FieldGroup, kind: FieldKind, path: String, shape: XMPShape,
             fallback: (dictionary: CFString, key: CFString)?) {
            self.id = id
            self.label = label
            self.group = group
            self.kind = kind
            self.path = path
            self.shape = shape
            self.fallback = fallback
        }

        init(_ field: GeneralField, path: String, shape: XMPShape, fallback: (dictionary: CFString, key: CFString)?) {
            self.init(id: field.rawValue, label: field.label, group: .general, kind: field.kind, path: path, shape: shape, fallback: fallback)
        }

        var key: FieldKey {
            group == .general ? FieldKey(provider: GeneralField.providerID, id: id) : FieldKey(provider: "imageio", id: id)
        }

        var order: Int? { group == .general ? GeneralField(rawValue: id)?.order : nil }
    }

    private static let mappings: [Mapping] = [
        Mapping(.title, path: "dc:title", shape: .langAlt,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCObjectName)),
        Mapping(.artist, path: "dc:creator", shape: .seq,
                fallback: (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFArtist)),
        Mapping(.description, path: "dc:description", shape: .langAlt,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCCaptionAbstract)),
        Mapping(.keywords, path: "dc:subject", shape: .bag,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCKeywords)),
        Mapping(.copyright, path: "dc:rights", shape: .langAlt,
                fallback: (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFCopyright)),
        Mapping(.date, path: "photoshop:DateCreated", shape: .text,
                fallback: (kCGImagePropertyExifDictionary, kCGImagePropertyExifDateTimeOriginal)),
        Mapping(.rating, path: "xmp:Rating", shape: .text, fallback: nil),
        Mapping(id: "headline", label: "Headline", group: .photo, kind: .text, path: "photoshop:Headline", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCHeadline)),
        Mapping(id: "credit", label: "Credit", group: .photo, kind: .text, path: "photoshop:Credit", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCCredit)),
        Mapping(id: "source", label: "Source", group: .photo, kind: .text, path: "photoshop:Source", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCSource)),
        Mapping(id: "city", label: "City", group: .photo, kind: .text, path: "photoshop:City", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCCity)),
        Mapping(id: "state", label: "State", group: .photo, kind: .text, path: "photoshop:State", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCProvinceState)),
        Mapping(id: "country", label: "Country", group: .photo, kind: .text, path: "photoshop:Country", shape: .text,
                fallback: (kCGImagePropertyIPTCDictionary, kCGImagePropertyIPTCCountryPrimaryLocationName)),
        Mapping(id: "label", label: "Label", group: .photo, kind: .text, path: "xmp:Label", shape: .text, fallback: nil),
        Mapping(id: "software", label: "Software", group: .photo, kind: .text, path: "xmp:CreatorTool", shape: .text,
                fallback: (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFSoftware)),
        Mapping(id: "userComment", label: "User comment", group: .photo, kind: .multiline, path: "exif:UserComment", shape: .text,
                fallback: (kCGImagePropertyExifDictionary, kCGImagePropertyExifUserComment)),
    ]

    func supports(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else { return false }
        return Self.readableTypes.contains(type.identifier)
    }

    private func key(_ id: String) -> FieldKey { FieldKey(provider: self.id, id: id) }

    // MARK: Read

    func read(url: URL) throws -> ProviderData {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw MetadataError("ImageIO could not open \(url.lastPathComponent)")
        }
        let type = CGImageSourceGetType(source).map { $0 as String } ?? ""
        let writable = Self.writableTypes.contains(type)
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]

        var data = ProviderData()
        var order = 0
        for mapping in Self.mappings {
            let strings = Self.currentStrings(for: mapping, metadata: metadata, properties: properties)
            let value: FieldValue?
            if mapping.kind == .list {
                value = strings.isEmpty ? nil : .list(strings)
            } else {
                value = strings.isEmpty ? nil : .text(strings.joined(separator: "; "))
            }
            data.add(FieldSpec(key: mapping.key, label: mapping.label, group: mapping.group, kind: mapping.kind, writable: writable, order: mapping.order ?? order), value)
            order += 1
        }

        for (id, label, text) in Self.technical(properties) {
            data.add(FieldSpec(key: key(id), label: label, group: .technical, kind: .text, writable: false, order: order), .text(text))
            order += 1
        }

        if let metadata {
            var raw: [(String, FieldValue, FieldKind)] = []
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                let path = path as String
                guard !path.hasPrefix("iio:") else { return true }
                let strings = Self.strings(from: CGImageMetadataTagCopyValue(tag))
                guard !strings.isEmpty else { return true }
                switch CGImageMetadataTagGetType(tag) {
                case .string, .default, .alternateText:
                    raw.append((path, .text(strings.joined(separator: "; ")), .text))
                case .arrayOrdered, .arrayUnordered, .alternateArray:
                    raw.append((path, .list(strings), .list))
                default:
                    break
                }
                return true
            }
            for (path, value, kind) in raw.sorted(by: { $0.0 < $1.0 }) {
                data.add(FieldSpec(key: key("xmp:" + path), label: path, group: .raw, kind: kind, writable: writable, order: order), value)
                order += 1
            }
        }
        if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            for (name, value) in iptc.sorted(by: { ($0.key as String) < ($1.key as String) }) {
                let strings = Self.strings(from: value as CFTypeRef?)
                guard !strings.isEmpty else { continue }
                let label = "IPTC " + (name as String)
                data.add(
                    FieldSpec(key: key("iptc:" + (name as String)), label: label, group: .raw, kind: strings.count > 1 ? .list : .text, writable: false, order: order),
                    strings.count > 1 ? .list(strings) : .text(strings[0])
                )
                order += 1
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
        if let fallback = mapping.fallback, let dictionary = properties[fallback.dictionary] as? [CFString: Any] {
            return strings(from: dictionary[fallback.key] as CFTypeRef?)
        }
        return []
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

    private static func technical(_ properties: [CFString: Any]) -> [(String, String, String)] {
        var result: [(String, String, String)] = []
        if let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            result.append(("dimensions", "Dimensions", "\(width) × \(height)"))
        }
        if let dpi = properties[kCGImagePropertyDPIWidth] as? Double, dpi > 0 {
            result.append(("dpi", "Resolution", "\(Int(dpi.rounded())) dpi"))
        }
        if let model = properties[kCGImagePropertyColorModel] as? String {
            let depth = (properties[kCGImagePropertyDepth] as? Int).map { " \($0)-bit" } ?? ""
            result.append(("colorModel", "Color", model + depth))
        }
        if let profile = properties[kCGImagePropertyProfileName] as? String {
            result.append(("profile", "Color profile", profile))
        }
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation != 1 {
            result.append(("orientation", "Orientation", "\(orientation)"))
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let make = tiff[kCGImagePropertyTIFFMake] as? String ?? ""
        let model = tiff[kCGImagePropertyTIFFModel] as? String ?? ""
        if !make.isEmpty || !model.isEmpty {
            let camera = model.hasPrefix(make) ? model : [make, model].filter { !$0.isEmpty }.joined(separator: " ")
            result.append(("camera", "Camera", camera))
        }
        if let lens = exif[kCGImagePropertyExifLensModel] as? String, !lens.isEmpty {
            result.append(("lens", "Lens", lens))
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
            result.append(("exposure", "Exposure", exposure.joined(separator: ", ")))
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
           let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latitudeSign = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -1.0 : 1.0
            let longitudeSign = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -1.0 : 1.0
            result.append(("gps", "Location", String(format: "%.5f, %.5f", latitude * latitudeSign, longitude * longitudeSign)))
        }
        return result
    }

    // MARK: Write

    func write(url: URL, changes: [FieldKey: FieldValue?]) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) else {
            throw MetadataError("ImageIO could not open \(url.lastPathComponent)")
        }
        guard Self.writableTypes.contains(type as String) else {
            throw MetadataError("ImageIO cannot write \(url.pathExtension.uppercased()) files")
        }
        let existing = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        guard let metadata = existing.map({ CGImageMetadataCreateMutableCopy($0) }) ?? CGImageMetadataCreateMutable() else {
            throw MetadataError("Could not prepare metadata")
        }
        var error: Unmanaged<CFError>?
        for (prefix, namespace) in Self.namespaces {
            _ = CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix as CFString, &error)
            error = nil
        }
        if CGImageMetadataCopyTagWithPath(metadata, nil, "iio:hasXMP" as CFString) == nil {
            _ = CGImageMetadataRegisterNamespaceForPrefix(metadata, Self.iioNamespace, "iio" as CFString, &error)
            error = nil
            _ = CGImageMetadataSetValueWithPath(metadata, nil, "iio:hasXMP" as CFString, kCFBooleanTrue)
        }

        // Keep IPTC-only values: ImageIO rebuilds the IPTC block from XMP, so mirror them into XMP first.
        for mapping in Self.mappings where mapping.fallback?.dictionary == kCGImagePropertyIPTCDictionary {
            let hasXMP = existing.flatMap { CGImageMetadataCopyTagWithPath($0, nil, mapping.path as CFString) } != nil
            guard !hasXMP, let fallback = mapping.fallback,
                  let dictionary = properties[fallback.dictionary] as? [CFString: Any] else { continue }
            let strings = Self.strings(from: dictionary[fallback.key] as CFTypeRef?)
            guard !strings.isEmpty else { continue }
            try apply(mapping.kind == .list ? .list(strings) : .text(strings.joined(separator: "; ")), path: mapping.path, shape: mapping.shape, to: metadata)
        }

        for (fieldKey, entry) in changes {
            let value: FieldValue? = entry
            if fieldKey.id.hasPrefix("xmp:") {
                let path = String(fieldKey.id.dropFirst(4))
                let fallbackShape: XMPShape
                if case .list? = value { fallbackShape = .seq } else { fallbackShape = .text }
                let shape = Self.shape(ofExisting: path, in: existing) ?? fallbackShape
                try apply(value, path: path, shape: shape, to: metadata)
            } else if let mapping = Self.mappings.first(where: { $0.key == fieldKey }) {
                try apply(value, path: mapping.path, shape: mapping.shape, to: metadata)
            }
        }

        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).meteedit-\(UUID().uuidString.prefix(8))")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, 1, nil) else {
            throw MetadataError("Could not create \(temporary.lastPathComponent)")
        }
        let options: [CFString: Any] = [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: false]
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
            try? FileManager.default.removeItem(at: temporary)
            let reason = error?.takeRetainedValue().localizedDescription ?? "unknown error"
            throw MetadataError("ImageIO could not write \(url.lastPathComponent): \(reason)")
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
            ok = CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, strings.joined(separator: "; ") as CFString)
        case .langAlt:
            _ = CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
            ok = CGImageMetadataSetValueWithPath(metadata, nil, "\(path)[x-default]" as CFString, strings.joined(separator: "; ") as CFString)
        case .seq, .bag:
            let parts = path.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let namespace = Self.namespaces[parts[0]] else {
                throw MetadataError("Unknown XMP namespace in \(path)")
            }
            let tagType: CGImageMetadataType = shape == .seq ? .arrayOrdered : .arrayUnordered
            guard let tag = CGImageMetadataTagCreate(namespace, parts[0] as CFString, parts[1] as CFString, tagType, strings as CFArray) else {
                throw MetadataError("Could not create tag \(path)")
            }
            ok = CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag)
        }
        guard ok else { throw MetadataError("Could not set \(path)") }
    }
}
