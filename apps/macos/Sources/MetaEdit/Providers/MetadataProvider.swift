import Foundation

/// A provider owns one metadata container (audio tags, image metadata, file attributes).
protocol MetadataProvider: AnyObject {
    var id: String { get }
    func supports(_ url: URL) -> Bool
    func read(url: URL) throws -> ProviderData
    /// Writes changes (a nil value removes the tag). Returns the file URL afterwards; it changes on rename.
    func write(url: URL, changes: [FieldKey: FieldValue?]) throws -> URL
}

struct ProviderData {
    var specs: [FieldSpec] = []
    var values: [FieldKey: FieldValue] = [:]

    mutating func add(_ spec: FieldSpec, _ value: FieldValue?) {
        specs.append(spec)
        if let value, !value.isEmpty {
            values[spec.key] = value
        }
    }
}

struct MetadataError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum ProviderRegistry {
    static let tagLib = TagLibProvider()
    static let imageIO = ImageIOProvider()
    static let file = FileAttributesProvider()

    /// Providers for a file, in write order. The file attributes provider goes last because it may rename.
    static func providers(for url: URL) -> [any MetadataProvider] {
        var list: [any MetadataProvider] = []
        if tagLib.supports(url) { list.append(tagLib) }
        if imageIO.supports(url) { list.append(imageIO) }
        list.append(file)
        return list
    }
}
