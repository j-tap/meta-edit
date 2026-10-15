import Foundation
import UniformTypeIdentifiers

/// Filesystem attributes available for every file: name, dates, Finder tags, Finder comment, "where from".
struct FileAttributesProvider: MetadataProvider {
    /// Fields that set file dates explicitly, so saving must not restore the old modification date.
    static let dateKeys: Set<FieldKey> = [FileField.created.key, FileField.modified.key]

    let id = ProviderID.file

    private static let finderCommentAttribute = "com.apple.metadata:kMDItemFinderComment"
    private static let whereFromsAttribute = "com.apple.metadata:kMDItemWhereFroms"
    private static let userTagsAttribute = "com.apple.metadata:_kMDItemUserTags"
    /// Colour indexes Finder assigns to its default tags, so typing "Red" gets the red dot.
    private static let standardTagColors = ["gray": 1, "grey": 1, "green": 2, "purple": 3, "blue": 4, "yellow": 5, "red": 6, "orange": 7]

    func supports(_ url: URL) -> Bool { true }

    func read(url: URL) throws -> ProviderData {
        let values = try url.resourceValues(forKeys: [
            .nameKey, .creationDateKey, .contentModificationDateKey, .tagNamesKey,
            .fileSizeKey, .contentTypeKey, .localizedTypeDescriptionKey,
        ])
        var data = ProviderData()
        data.add(FileField.name.spec(), .text(values.name ?? url.lastPathComponent))
        data.add(FileField.tags.spec(), .list(values.tagNames ?? []))
        data.add(FileField.comment.spec(), (Xattr.plist(url, Self.finderCommentAttribute) as? String).map(FieldValue.text))
        data.add(FileField.whereFrom.spec(), .list(Xattr.plist(url, Self.whereFromsAttribute) as? [String] ?? []))
        data.add(FileField.created.spec(), values.creationDate.map(FieldValue.date))
        data.add(FileField.modified.spec(), values.contentModificationDate.map(FieldValue.date))
        data.add(FileField.folder.spec(), .text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath))
        data.add(FileField.size.spec(), .text(ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file)))
        data.add(FileField.contentType.spec(), .text(values.localizedTypeDescription ?? values.contentType?.identifier ?? ""))
        return data
    }

    func write(url: URL, changes: [FieldKey: FieldValue?]) throws -> URL {
        var target = url
        var resourceValues = URLResourceValues()
        var touched = false
        for (key, value) in changes {
            guard case .file(let field) = key else { continue }
            switch field {
            case .created:
                if case .date(let date)? = value {
                    resourceValues.creationDate = date
                    touched = true
                }
            case .modified:
                if case .date(let date)? = value {
                    resourceValues.contentModificationDate = date
                    touched = true
                }
            case .tags:
                try writeTags(value?.strings ?? [], to: url)
            case .comment:
                let text = value?.displayText ?? ""
                try Xattr.setPlist(url, Self.finderCommentAttribute, text.isEmpty ? nil : text)
            case .whereFrom:
                let list = value?.strings ?? []
                try Xattr.setPlist(url, Self.whereFromsAttribute, list.isEmpty ? nil : list)
            case .name:
                // Renamed last, after everything else was written under the old name.
                break
            case .folder, .size, .contentType:
                break
            }
        }
        if touched {
            try target.setResourceValues(resourceValues)
        }
        if case .text(let newName)?? = changes[FileField.name.key] {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
                throw MetadataError(tr("Invalid file name"))
            }
            let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed)
            if destination.path != url.path {
                try rename(url, to: destination)
                target = destination
            }
        }
        return target
    }

    private func rename(_ url: URL, to destination: URL) throws {
        if Self.isSameFile(url, destination) {
            // Only the letter case changes. On a case-insensitive volume the destination "exists" as this very
            // file, so the existence check below would refuse the rename; rename(2) handles it.
            guard Foundation.rename(url.path, destination.path) == 0 else {
                throw MetadataError(tr("Could not rename %@: %@", url.lastPathComponent, String(cString: strerror(errno))))
            }
            return
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw MetadataError(tr("A file named %@ already exists", destination.lastPathComponent))
        }
        try FileManager.default.moveItem(at: url, to: destination)
    }

    private static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        func identifier(_ url: URL) -> (any NSObjectProtocol)? {
            (try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
        }
        guard let first = identifier(a), let second = identifier(b) else { return false }
        return first.isEqual(second)
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
