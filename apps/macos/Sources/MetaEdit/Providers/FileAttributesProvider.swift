import Foundation
import UniformTypeIdentifiers

/// Filesystem attributes available for every file: name, dates, Finder tags, Finder comment, "where from".
final class FileAttributesProvider: MetadataProvider {
    static let providerID = "file"
    static let nameKey = FieldKey(provider: providerID, id: "name")

    let id = FileAttributesProvider.providerID

    private static let finderCommentAttribute = "com.apple.metadata:kMDItemFinderComment"
    private static let whereFromsAttribute = "com.apple.metadata:kMDItemWhereFroms"
    private static let userTagsAttribute = "com.apple.metadata:_kMDItemUserTags"
    /// Colour indexes Finder assigns to its default tags, so typing "Red" gets the red dot.
    private static let standardTagColors = ["gray": 1, "grey": 1, "green": 2, "purple": 3, "blue": 4, "yellow": 5, "red": 6, "orange": 7]

    func supports(_ url: URL) -> Bool { true }

    private func key(_ id: String) -> FieldKey { FieldKey(provider: self.id, id: id) }

    func read(url: URL) throws -> ProviderData {
        let values = try url.resourceValues(forKeys: [
            .nameKey, .creationDateKey, .contentModificationDateKey, .tagNamesKey,
            .fileSizeKey, .contentTypeKey, .localizedTypeDescriptionKey,
        ])
        var data = ProviderData()
        data.add(FieldSpec(key: Self.nameKey, label: "Name", group: .file, kind: .text, order: 0), .text(values.name ?? url.lastPathComponent))
        data.add(FieldSpec(key: key("tags"), label: "Tags", group: .file, kind: .list, order: 1), .list(values.tagNames ?? []))
        data.add(
            FieldSpec(key: key("comment"), label: "Comment", group: .file, kind: .multiline, order: 2),
            (Xattr.plist(url, Self.finderCommentAttribute) as? String).map(FieldValue.text)
        )
        data.add(
            FieldSpec(key: key("whereFrom"), label: "Where from", group: .file, kind: .lines, order: 3),
            .list(Xattr.plist(url, Self.whereFromsAttribute) as? [String] ?? [])
        )
        data.add(FieldSpec(key: key("created"), label: "Created", group: .file, kind: .date, order: 4), values.creationDate.map(FieldValue.date))
        data.add(FieldSpec(key: key("modified"), label: "Modified", group: .file, kind: .date, order: 5), values.contentModificationDate.map(FieldValue.date))

        data.add(
            FieldSpec(key: key("path"), label: "Folder", group: .technical, kind: .text, writable: false, order: 1000),
            .text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
        )
        data.add(
            FieldSpec(key: key("size"), label: "Size", group: .technical, kind: .text, writable: false, order: 1001),
            .text(ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file))
        )
        data.add(
            FieldSpec(key: key("type"), label: "Kind", group: .technical, kind: .text, writable: false, order: 1002),
            .text(values.localizedTypeDescription ?? values.contentType?.identifier ?? "")
        )
        return data
    }

    func write(url: URL, changes: [FieldKey: FieldValue?]) throws -> URL {
        var target = url
        var resourceValues = URLResourceValues()
        var touched = false
        for (fieldKey, entry) in changes {
            let value: FieldValue? = entry
            switch fieldKey.id {
            case "created":
                if case .date(let date)? = value {
                    resourceValues.creationDate = date
                    touched = true
                }
            case "modified":
                if case .date(let date)? = value {
                    resourceValues.contentModificationDate = date
                    touched = true
                }
            case "tags":
                try writeTags(value?.strings ?? [], to: url)
            case "comment":
                let text = value?.displayText ?? ""
                try Xattr.setPlist(url, Self.finderCommentAttribute, text.isEmpty ? nil : text)
            case "whereFrom":
                let list = value?.strings ?? []
                try Xattr.setPlist(url, Self.whereFromsAttribute, list.isEmpty ? nil : list)
            default:
                break
            }
        }
        if touched {
            try target.setResourceValues(resourceValues)
        }
        if let entry = changes[Self.nameKey], case .text(let newName)? = entry {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
                throw MetadataError(tr("Invalid file name"))
            }
            let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed)
            if destination.path != url.path {
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    throw MetadataError(tr("A file named %@ already exists", trimmed))
                }
                try FileManager.default.moveItem(at: url, to: destination)
                target = destination
            }
        }
        return target
    }

    /// Finder stores tags as "Name\nColour" strings. Colours of kept tags are preserved; the
    /// setter of URLResourceValues.tagNames needs macOS 26, so the attribute is written directly.
    private func writeTags(_ names: [String], to url: URL) throws {
        let existing = Xattr.plist(url, Self.userTagsAttribute) as? [String] ?? []
        var colors: [String: String] = [:]
        for entry in existing {
            let parts = entry.split(separator: "\n", maxSplits: 1)
            if parts.count == 2 { colors[String(parts[0])] = String(parts[1]) }
        }
        let encoded = names.map { name -> String in
            if let color = colors[name] { return "\(name)\n\(color)" }
            if let color = Self.standardTagColors[name.lowercased()] { return "\(name)\n\(color)" }
            return name
        }
        try Xattr.setPlist(url, Self.userTagsAttribute, encoded.isEmpty ? nil : encoded)
    }
}
