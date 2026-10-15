import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import MeteEdit

@Suite(.serialized)
final class ProviderTests {
    static let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    private let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("meteedit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func copy(_ name: String) throws -> URL {
        let destination = tempDir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(name), to: destination)
        return destination
    }

    private func load(_ url: URL) -> FileItem {
        let item = FileItem(url: url)
        item.load()
        return item
    }

    private func key(_ provider: String, _ id: String) -> FieldKey { FieldKey(provider: provider, id: id) }

    /// MD5 of the decoded audio and video streams via ffmpeg; empty when ffmpeg is not installed (check skipped).
    private func decodedDigest(_ url: URL) throws -> String {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let ffmpeg = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        // Audio plus real video streams only: an added cover shows up as an attached picture stream.
        process.arguments = ["-v", "error", "-i", url.path, "-map", "0:a?", "-map", "0:V?", "-f", "md5", "-"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func pixels(_ url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MetadataError("cannot decode \(url.lastPathComponent)")
        }
        var data = Data(count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    // MARK: Audio and video containers

    @Test func readsMP3Tags() throws {
        let item = load(try copy("sample.mp3"))
        #expect(item.error == nil)
        #expect(item.values[key("general", "title")] == .text("Sine MP3"))
        #expect(item.values[key("general", "artist")] == .text("Sample Artist"))
        #expect(item.values[key("general", "album")] == .text("Samples"))
        #expect(item.values[key("general", "genre")] == .text("Test"))
        #expect(item.values[key("taglib", "duration")] != nil)
        #expect(item.values[key("file", "name")] != nil)
    }

    @Test func audioRoundTrip() throws {
        let cover = try Data(contentsOf: Self.fixtures.appendingPathComponent("sample.png"))
        for name in ["sample.mp3", "sample.flac", "sample.ogg", "sample.opus", "sample.m4a", "sample.wav", "sample.aiff", "sample.mp4", "sample.mkv"] {
            let url = try copy(name)
            let before = try decodedDigest(url)
            let item = load(url)
            #expect(item.error == nil, Comment(rawValue: name))
            let edits: [(String, FieldValue)] = [
                ("title", .text("New Title")), ("artist", .text("New Artist")), ("album", .text("Album X")),
                ("genre", .text("Jazz")), ("track", .text("3/12")), ("comment", .text("Hello\nWorld")),
                ("keywords", .list(["one", "two"])), ("cover", .image(cover, mime: "image/png")),
            ]
            for (id, value) in edits { item.stage(value, for: key("general", id)) }
            #expect(item.isDirty, Comment(rawValue: name))
            try item.save(preserveModificationDate: true, onlyWhereEmpty: [])
            #expect(item.error == nil, Comment(rawValue: name))
            #expect(!(item.isDirty), Comment(rawValue: name))
            for (id, value) in edits where id != "cover" {
                #expect(item.values[key("general", id)] == value, "\(name) \(id)")
            }
            if case .image(let data, _)? = item.values[key("general", "cover")] {
                #expect(data == cover, "\(name) cover")
            } else {
                Issue.record("\(name): cover missing after save")
            }
            #expect(try decodedDigest(url) == before, "\(name): decoded stream changed")
        }
    }

    @Test func removingTagsAndCover() throws {
        let url = try copy("sample.mp3")
        let item = load(url)
        item.stage(nil, for: key("general", "title"))
        item.stage(nil, for: key("general", "genre"))
        try item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(item.values[key("general", "title")] == nil)
        #expect(item.values[key("general", "genre")] == nil)
        #expect(item.values[key("general", "artist")] == .text("Sample Artist"))
    }

    @Test func preservesModificationDate() throws {
        let url = try copy("sample.flac")
        let past = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
        let item = load(url)
        item.stage(.text("T"), for: key("general", "title"))
        try item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        #expect(abs((modified.timeIntervalSince1970) - (past.timeIntervalSince1970)) <= 1)
    }

    // MARK: Images

    @Test func imageRoundTrip() throws {
        for name in ["sample.jpg", "sample.png", "sample.tiff", "sample.heic"] {
            let url = try copy(name)
            let before = try pixels(url)
            let item = load(url)
            #expect(item.error == nil, Comment(rawValue: name))
            let edits: [(String, FieldValue)] = [
                ("title", .text("Photo title")), ("description", .text("A description")),
                ("keywords", .list(["alpha", "beta"])), ("copyright", .text("(c) Me")),
                ("rating", .text("4")), ("city", .text("Berlin")), ("artist", .text("Jane")),
            ]
            for (id, value) in edits {
                let provider = ["city"].contains(id) ? "imageio" : "general"
                item.stage(value, for: key(provider, id))
            }
            try item.save(preserveModificationDate: false, onlyWhereEmpty: [])
            #expect(item.error == nil, Comment(rawValue: name))
            for (id, value) in edits {
                let provider = ["city"].contains(id) ? "imageio" : "general"
                #expect(item.values[key(provider, id)] == value, "\(name) \(id)")
            }
            #expect(try pixels(url) == before, "\(name): pixels changed")

            item.stage(nil, for: key("imageio", "city"))
            try item.save(preserveModificationDate: false, onlyWhereEmpty: [])
            #expect(item.values[key("imageio", "city")] == nil, Comment(rawValue: name))
            #expect(item.values[key("general", "title")] == .text("Photo title"), Comment(rawValue: name))
        }
    }

    @Test func richJPEGKeepsExifAndIPTC() throws {
        let url = try copy("rich.jpg")
        let item = load(url)
        #expect(item.values[key("general", "title")] == .text("IPTC title"))
        #expect(item.values[key("general", "description")] == .text("Exif description"))
        #expect(item.values[key("general", "keywords")] == .list(["iptc1", "iptc2"]))
        #expect(item.values[key("imageio", "city")] == .text("Paris"))
        #expect(item.values[key("imageio", "camera")] == .text("Canon EOS R5"))
        #expect(item.values[key("imageio", "lens")] == .text("RF 50mm"))

        item.stage(.text("Edited title"), for: key("general", "title"))
        try item.save(preserveModificationDate: false, onlyWhereEmpty: [])
        #expect(item.error == nil)
        #expect(item.values[key("general", "title")] == .text("Edited title"))
        #expect(item.values[key("general", "description")] == .text("Exif description"))
        #expect(item.values[key("general", "keywords")] == .list(["iptc1", "iptc2"]))
        #expect(item.values[key("imageio", "city")] == .text("Paris"))
        #expect(item.values[key("imageio", "headline")] == .text("IPTC headline"))
        #expect(item.values[key("imageio", "credit")] == .text("IPTC credit"))
        #expect(item.values[key("imageio", "camera")] == .text("Canon EOS R5"))
        #expect(item.values[key("imageio", "lens")] == .text("RF 50mm"))
        #expect(item.values[key("imageio", "exposure")] == .text("1/200 s, f/2.8, ISO 100, 50 mm"))
        #expect(item.values[key("imageio", "gps")] == .text("52.52000, 13.40500"))
        #expect(item.values[key("imageio", "label")] == .text("Green"))
        #expect(item.values[key("imageio", "xmp:xmpMM:DocumentID")] == .text("xmp.did:1234"))
    }

    // MARK: File attributes

    @Test func fileAttributesAndRename() throws {
        let url = try copy("sample.txt")
        let item = load(url)
        #expect(item.error == nil)
        item.stage(.list(["Red", "Project"]), for: key("file", "tags"))
        item.stage(.text("A Finder comment"), for: key("file", "comment"))
        item.stage(.list(["https://example.com/a"]), for: key("file", "whereFrom"))
        try item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(item.error == nil)
        #expect(item.values[key("file", "tags")] == .list(["Red", "Project"]))
        #expect(item.values[key("file", "comment")] == .text("A Finder comment"))
        #expect(item.values[key("file", "whereFrom")] == .list(["https://example.com/a"]))
        #expect(Xattr.plist(url, "com.apple.metadata:_kMDItemUserTags") as? [String] == ["Red\n6", "Project"])

        item.stage(.text("renamed.txt"), for: FileAttributesProvider.nameKey)
        try item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(item.url.lastPathComponent == "renamed.txt")
        #expect(FileManager.default.fileExists(atPath: item.url.path))
        #expect(!(FileManager.default.fileExists(atPath: url.path)))
        #expect(item.values[key("file", "comment")] == .text("A Finder comment"))
    }

    // MARK: Batch editing

    @MainActor
    @Test func batchMixedValuesAndOnlyWhereEmpty() throws {
        let a = load(try copy("sample.mp3"))
        let b = load(try copy("sample.flac"))
        let title = key("general", "title")
        let genre = key("general", "genre")

        func field(_ key: FieldKey) -> FieldState {
            SelectionFields.compute([a, b]).flatMap(\.fields).first { $0.id == key }!
        }
        #expect(field(title).isMixed)
        #expect(field(genre).isMixed)
        #expect(field(genre).mixedValues.count == 2)
        #expect(SelectionFields.compute([a, b]).flatMap(\.fields).first { $0.id == FileAttributesProvider.nameKey } == nil)

        let state = AppState()
        state.stage(.text("Rock"), for: genre, in: [a, b])
        #expect(field(genre).pending == .uniform(.text("Rock")))
        #expect(!(field(genre).isMixed))

        state.performSave([a, b], onlyWhereEmpty: [genre])
        #expect(a.values[genre] == .text("Test"))
        #expect(b.values[genre] == .text("Rock"))
        #expect(!(a.isDirty))
        #expect(!(b.isDirty))

        state.stage(.text("Same"), for: title, in: [a, b])
        state.performSave([a, b], onlyWhereEmpty: [])
        #expect(field(title).original == .same(.text("Same")))
    }
}
