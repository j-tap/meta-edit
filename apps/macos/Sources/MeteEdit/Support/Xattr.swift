import Foundation

/// Extended attribute helpers (Finder comment, Finder tags storage, "where from").
enum Xattr {
    static func get(_ url: URL, _ name: String) -> Data? {
        let path = url.path
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, length, 0, 0) }
        guard read >= 0 else { return nil }
        data.count = read
        return data
    }

    static func set(_ url: URL, _ name: String, _ data: Data?) throws {
        let path = url.path
        if let data {
            let result = data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, 0) }
            guard result == 0 else {
                throw MetadataError("Could not write \(name): \(String(cString: strerror(errno)))")
            }
        } else {
            let result = removexattr(path, name, 0)
            guard result == 0 || errno == ENOATTR else {
                throw MetadataError("Could not remove \(name): \(String(cString: strerror(errno)))")
            }
        }
    }

    static func plist(_ url: URL, _ name: String) -> Any? {
        guard let data = get(url, name) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    static func setPlist(_ url: URL, _ name: String, _ object: Any?) throws {
        guard let object else {
            try set(url, name, nil)
            return
        }
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
        try set(url, name, data)
    }
}
