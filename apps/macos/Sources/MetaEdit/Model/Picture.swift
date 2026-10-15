import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An embedded picture, such as a cover, as the editor keeps it.
///
/// Covers are often a megabyte or more and a selection can hold thousands of files, so a picture read from a
/// file keeps only what the editor shows and compares: a thumbnail, the type, the size and a digest of the
/// bytes. The bytes stay in the file and are read again when they are needed: to export the picture or to
/// copy it into other files. A picture the user picks keeps its bytes until it is written.
/// See docs/batch-editing.md.
struct Picture: Sendable {
    enum Source: Sendable {
        /// The bytes themselves: a picture the user picked.
        case bytes(Data)
        /// The cover embedded in this file.
        case file(URL)
    }

    let source: Source
    let mimeType: String
    let byteCount: Int
    /// SHA-256 of the bytes. Two pictures are the same when their digests and types match.
    let digest: Data
    let pixelWidth: Int?
    let pixelHeight: Int?
    /// JPEG, or PNG when the picture has transparency, at most `thumbnailPixelSize` on the long side.
    let thumbnail: Data?

    /// Twice the 128 point cover well, so thumbnails are sharp on Retina displays.
    static let thumbnailPixelSize = 256
    private static let thumbnailQuality = 0.85

    /// Thumbnails by digest. Tracks of an album usually share a cover, so they share one thumbnail instead of
    /// each making and keeping its own. NSCache gives memory back under pressure and, as its documentation
    /// states, may be used from several threads without locking; it is not marked Sendable, hence the unsafe.
    nonisolated(unsafe) private static let thumbnails = NSCache<NSData, NSData>()

    /// Describes `bytes`. `mimeType` is the type a tag declares; without one, the type is taken from the bytes.
    init(bytes: Data, mimeType: String?, source: Source) {
        let image = CGImageSourceCreateWithData(bytes as CFData, nil)
        let properties = image.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        let detectedType = image.flatMap(CGImageSourceGetType).flatMap { UTType($0 as String) }
        self.source = source
        self.mimeType = mimeType ?? detectedType?.preferredMIMEType ?? FieldValue.fallbackImageMIMEType
        self.byteCount = bytes.count
        let digest = Data(SHA256.hash(data: bytes))
        self.digest = digest
        self.pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int
        self.pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int
        if let cached = Self.thumbnails.object(forKey: digest as NSData) {
            self.thumbnail = cached as Data
        } else {
            self.thumbnail = image.flatMap(Self.thumbnail)
            if let thumbnail { Self.thumbnails.setObject(thumbnail as NSData, forKey: digest as NSData) }
        }
    }

    /// Whether the bytes are a picture ImageIO can show.
    var isDecodable: Bool { thumbnail != nil }

    /// The full bytes: kept in memory for a picked picture, read from the file otherwise.
    /// Throws when the file no longer holds this picture, so a changed file is never copied silently.
    func bytes() throws -> Data {
        switch source {
        case .bytes(let bytes):
            return bytes
        case .file(let url):
            let bytes = try TagLibProvider.coverBytes(of: url)
            guard Data(SHA256.hash(data: bytes)) == digest else {
                throw MetadataError(tr("The cover of %@ changed since it was loaded", url.lastPathComponent))
            }
            return bytes
        }
    }

    private static func thumbnail(of image: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary) else { return nil }
        let opaque: Set<CGImageAlphaInfo> = [.none, .noneSkipFirst, .noneSkipLast]
        let type: UTType = opaque.contains(thumbnail.alphaInfo) ? .jpeg : .png
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: thumbnailQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

extension Picture: Hashable {
    static func == (lhs: Picture, rhs: Picture) -> Bool {
        lhs.digest == rhs.digest && lhs.mimeType == rhs.mimeType
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(digest)
        hasher.combine(mimeType)
    }
}
