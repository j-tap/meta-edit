import CoreGraphics
import CTagLib
import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import MetaEdit

@Suite(.serialized)
@MainActor
final class ProviderTests {
    static let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
    private let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("metaedit-tests-\(UUID().uuidString)")
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

    /// A picture the user picked, as CoverField stages it.
    private func picked(_ bytes: Data) -> FieldValue {
        .picture(Picture(bytes: bytes, mimeType: nil, source: .bytes(bytes)))
    }

    /// A JPEG cover of `side` × `side` pixels with enough detail to be realistically large.
    private func largeCover(side: Int = 1200) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            context.setFillColor(red: .random(in: 0...1, using: &generator), green: .random(in: 0...1, using: &generator),
                                 blue: .random(in: 0...1, using: &generator), alpha: 1)
            context.fill(CGRect(x: .random(in: 0..<Double(side)), y: .random(in: 0..<Double(side)), width: 40, height: 40))
        }
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

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

    @Test func readsMP3Tags() async throws {
        let item = load(try copy("sample.mp3"))
        #expect(item.error == nil)
        #expect(item.values[.general(.title)] == .text("Sine MP3"))
        #expect(item.values[.general(.artist)] == .text("Sample Artist"))
        #expect(item.values[.general(.album)] == .text("Samples"))
        #expect(item.values[.general(.genre)] == .text("Test"))
        #expect(item.values[.tagLib(.duration)] != nil)
        #expect(item.values[.file(.name)] != nil)
    }

    @Test func audioRoundTrip() async throws {
        let cover = try Data(contentsOf: Self.fixtures.appendingPathComponent("sample.png"))
        for name in ["sample.mp3", "sample.flac", "sample.ogg", "sample.opus", "sample.m4a", "sample.wav", "sample.aiff", "sample.mp4", "sample.mkv"] {
            let url = try copy(name)
            let before = try decodedDigest(url)
            let item = load(url)
            #expect(item.error == nil, Comment(rawValue: name))
            let isVideo = ["sample.mp4", "sample.mkv"].contains(name)
            var edits: [(GeneralField, FieldValue)] = [
                (.title, .text("New Title")), (.artist, .text("New Artist")), (.genre, .text("Jazz")),
                (.comment, .text("Hello\nWorld")), (.cover, picked(cover)),
            ]
            edits += isVideo
                ? [(.description, .text("About this video"))]
                : [(.album, .text("Album X")), (.track, .text("3/12"))]
            for (field, _) in edits {
                #expect(item.supports(field.key), "\(name) \(field)")
            }
            for (field, value) in edits { item.stage(value, for: field.key) }
            #expect(item.isDirty, Comment(rawValue: name))
            try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
            #expect(item.error == nil, Comment(rawValue: name))
            #expect(!(item.isDirty), Comment(rawValue: name))
            for (field, value) in edits {
                #expect(item.values[field.key] == value, "\(name) \(field)")
            }
            if case .picture(let picture)? = item.values[.general(.cover)] {
                #expect(try picture.bytes() == cover, "\(name) cover")
            } else {
                Issue.record("\(name): cover missing after save")
            }
            #expect(try decodedDigest(url) == before, "\(name): decoded stream changed")
        }
    }

    @Test func fieldsDependOnFileType() async throws {
        let mp3 = load(try copy("sample.mp3"))
        #expect(mp3.supports(.general(.album)))
        #expect(mp3.supports(.tagLib(.lyrics)))
        #expect(!mp3.supports(.general(.description)))
        #expect(!mp3.supports(.general(.keywords)))
        #expect(!mp3.supports(.tagLib(.show)))
        #expect(mp3.spec(for: .general(.artist))?.label == "Artist")
        #expect(mp3.spec(for: .general(.date))?.label == "Year")

        let mp4 = load(try copy("sample.mp4"))
        #expect(mp4.supports(.general(.description)))
        #expect(mp4.supports(.tagLib(.show)))
        #expect(!mp4.supports(.general(.album)))
        #expect(!mp4.supports(.general(.track)))
        #expect(!mp4.supports(.tagLib(.lyrics)))
        #expect(mp4.spec(for: .general(.artist))?.label == "Author")

        let mkv = load(try copy("sample.mkv"))
        #expect(mkv.supports(.general(.description)))
        #expect(!mkv.supports(.tagLib(.show)))

        let png = load(try copy("sample.png"))
        #expect(png.supports(.general(.keywords)))
        #expect(png.supports(.image(.city)))
        #expect(!png.supports(.general(.album)))
        #expect(!png.supports(.general(.cover)))
        #expect(png.spec(for: .general(.date))?.label == "Date created")

        let txt = load(try copy("sample.txt"))
        #expect(txt.specs.allSatisfy { $0.group == .file || $0.group == .technical })
        #expect(txt.supports(.file(.whereFrom)))
    }

    @Test func videoShowFieldsRoundTrip() async throws {
        let item = load(try copy("sample.mp4"))
        item.stage(.text("Series"), for: .tagLib(.show))
        item.stage(.text("2"), for: .tagLib(.season))
        item.stage(.text("5"), for: .tagLib(.episode))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(item.error == nil)
        #expect(item.values[.tagLib(.show)] == .text("Series"))
        #expect(item.values[.tagLib(.season)] == .text("2"))
        #expect(item.values[.tagLib(.episode)] == .text("5"))
    }

    @Test func mixedSelectionJoinsDifferentLabels() async throws {
        let fields = SelectionFields.compute([load(try copy("sample.mp3")), load(try copy("sample.jpg"))]).flatMap(\.fields)
        let artist = fields.first { $0.id == .general(.artist) }
        #expect(artist?.label == tr("Artist") + " / " + tr("Author"))
        #expect(artist?.supportCount == 2)
        let album = fields.first { $0.id == .general(.album) }
        #expect(album?.supportCount == 1)
    }

    @Test func removingTagsAndCover() async throws {
        let url = try copy("sample.mp3")
        let item = load(url)
        item.stage(nil, for: .general(.title))
        item.stage(nil, for: .general(.genre))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(item.values[.general(.title)] == nil)
        #expect(item.values[.general(.genre)] == nil)
        #expect(item.values[.general(.artist)] == .text("Sample Artist"))
    }

    @Test func coverChangeKeepsOtherPictures() async throws {
        let url = try copy("sample.mp3")
        let front = try Data(contentsOf: Self.fixtures.appendingPathComponent("sample.png"))
        let back = try Data(contentsOf: Self.fixtures.appendingPathComponent("sample.jpg"))
        let item = load(url)
        item.stage(picked(front), for: .general(.cover))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        try appendPicture(back, mime: "image/jpeg", type: "Back Cover", to: url)
        #expect(try pictureTypes(url) == ["Front Cover", "Back Cover"])

        // Replacing the cover keeps the back cover.
        item.load()
        item.stage(picked(back), for: .general(.cover))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(try pictureTypes(url) == ["Front Cover", "Back Cover"])
        #expect(item.values[.general(.cover)] == picked(back))

        // Removing the cover removes only the first picture.
        item.stage(nil, for: .general(.cover))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(try pictureTypes(url) == ["Back Cover"])
    }

    private func appendPicture(_ data: Data, mime: String, type: String, to url: URL) throws {
        let file = try #require(taglib_file_new(url.path))
        defer { taglib_file_free(file) }
        let appended = TagLibProvider.withPictureAttributes(data: data, mime: mime, type: type) {
            taglib_complex_property_set_append(file, "PICTURE", $0) != 0
        }
        #expect(appended)
        #expect(taglib_file_save(file) != 0)
    }

    /// Picture types of every embedded picture, in file order.
    private func pictureTypes(_ url: URL) throws -> [String] {
        let file = try #require(taglib_file_new(url.path))
        defer { taglib_file_free(file) }
        guard let pictures = taglib_complex_property_get(file, "PICTURE") else { return [] }
        defer { taglib_complex_property_free(pictures) }
        var types: [String] = []
        var index = 0
        while let picture = pictures[index] {
            var attribute = 0
            while let entry = picture[attribute] {
                if String(cString: entry.pointee.key) == "pictureType" {
                    types.append(String(cString: entry.pointee.value.value.stringValue))
                }
                attribute += 1
            }
            index += 1
        }
        return types
    }

    @Test func preservesModificationDate() async throws {
        let url = try copy("sample.flac")
        let past = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
        let item = load(url)
        item.stage(.text("T"), for: .general(.title))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        #expect(abs((modified.timeIntervalSince1970) - (past.timeIntervalSince1970)) <= 1)
    }

    // MARK: Images

    @Test func imageRoundTrip() async throws {
        for name in ["sample.jpg", "sample.png", "sample.tiff", "sample.heic"] {
            let url = try copy(name)
            let before = try pixels(url)
            let item = load(url)
            #expect(item.error == nil, Comment(rawValue: name))
            let edits: [(FieldKey, FieldValue)] = [
                (.general(.title), .text("Photo title")), (.general(.description), .text("A description")),
                (.general(.keywords), .list(["alpha", "beta"])), (.general(.copyright), .text("(c) Me")),
                (.general(.rating), .text("4")), (.image(.city), .text("Berlin")), (.general(.artist), .text("Jane")),
            ]
            for (key, value) in edits {
                item.stage(value, for: key)
            }
            try await item.save(preserveModificationDate: false, onlyWhereEmpty: [])
            #expect(item.error == nil, Comment(rawValue: name))
            for (key, value) in edits {
                #expect(item.values[key] == value, "\(name) \(key)")
            }
            #expect(try pixels(url) == before, "\(name): pixels changed")

            item.stage(nil, for: .image(.city))
            try await item.save(preserveModificationDate: false, onlyWhereEmpty: [])
            #expect(item.values[.image(.city)] == nil, Comment(rawValue: name))
            #expect(item.values[.general(.title)] == .text("Photo title"), Comment(rawValue: name))
        }
    }

    @Test func richJPEGKeepsExifAndIPTC() async throws {
        let url = try copy("rich.jpg")
        let item = load(url)
        #expect(item.values[.general(.title)] == .text("IPTC title"))
        #expect(item.values[.general(.description)] == .text("Exif description"))
        #expect(item.values[.general(.keywords)] == .list(["iptc1", "iptc2"]))
        #expect(item.values[.image(.city)] == .text("Paris"))
        #expect(item.values[.image(.camera)] == .text("Canon EOS R5"))
        #expect(item.values[.image(.lens)] == .text("RF 50mm"))

        item.stage(.text("Edited title"), for: .general(.title))
        try await item.save(preserveModificationDate: false, onlyWhereEmpty: [])
        #expect(item.error == nil)
        #expect(item.values[.general(.title)] == .text("Edited title"))
        #expect(item.values[.general(.description)] == .text("Exif description"))
        #expect(item.values[.general(.keywords)] == .list(["iptc1", "iptc2"]))
        #expect(item.values[.image(.city)] == .text("Paris"))
        #expect(item.values[.image(.headline)] == .text("IPTC headline"))
        #expect(item.values[.image(.credit)] == .text("IPTC credit"))
        #expect(item.values[.image(.camera)] == .text("Canon EOS R5"))
        #expect(item.values[.image(.lens)] == .text("RF 50mm"))
        #expect(item.values[.image(.exposure)] == .text("1/200 s, f/2.8, ISO 100, 50 mm"))
        #expect(item.values[.image(.gps)] == .text("52.52000, 13.40500"))
        #expect(item.values[.image(.colorLabel)] == .text("Green"))
        #expect(item.values[.xmp("xmpMM:DocumentID")] == .text("xmp.did:1234"))
    }

    // MARK: File attributes

    @Test func fileAttributesAndRename() async throws {
        let url = try copy("sample.txt")
        let item = load(url)
        #expect(item.error == nil)
        item.stage(.list(["Red", "Project"]), for: .file(.tags))
        item.stage(.text("A Finder comment"), for: .file(.comment))
        item.stage(.list(["https://example.com/a"]), for: .file(.whereFrom))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(item.error == nil)
        #expect(item.values[.file(.tags)] == .list(["Red", "Project"]))
        #expect(item.values[.file(.comment)] == .text("A Finder comment"))
        #expect(item.values[.file(.whereFrom)] == .list(["https://example.com/a"]))
        #expect(Xattr.plist(url, "com.apple.metadata:_kMDItemUserTags") as? [String] == ["Red\n6", "Project"])

        item.stage(.text("renamed.txt"), for: FileField.name.key)
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(item.url.lastPathComponent == "renamed.txt")
        #expect(FileManager.default.fileExists(atPath: item.url.path))
        #expect(!(FileManager.default.fileExists(atPath: url.path)))
        #expect(item.values[.file(.comment)] == .text("A Finder comment"))
    }

    @Test func renameChangingOnlyLetterCase() async throws {
        let url = try copy("sample.txt")
        let item = load(url)
        item.stage(.text("SAMPLE.txt"), for: FileField.name.key)
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(item.error == nil)
        #expect(item.url.lastPathComponent == "SAMPLE.txt")
        let names = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        #expect(names.contains("SAMPLE.txt"))
        #expect(!names.contains("sample.txt"))
    }

    @Test func failedSaveRereadsTheFile() async throws {
        let url = try copy("sample.mp3")
        _ = try copy("sample.txt")
        let item = load(url)
        let title = FieldKey.general(.title)
        item.stage(.text("Written"), for: title)
        item.stage(.text("sample.txt"), for: FileField.name.key)
        await #expect(throws: MetadataError.self) {
            try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        }
        // TagLib wrote the title before the rename failed: it is on disk now and no longer staged.
        #expect(item.values[title] == .text("Written"))
        #expect(item.staged[title] == nil)
        #expect(item.staged[FileField.name.key] == .some(.text("sample.txt")))
        #expect(item.error != nil)
    }

    @Test func imageWriteKeepsWhereFrom() async throws {
        let url = try copy("sample.jpg")
        let item = load(url)
        item.stage(.list(["https://example.com/a,b?c=1", "https://example.com/"]), for: .file(.whereFrom))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        item.stage(.text("New title"), for: .general(.title))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(item.error == nil)
        #expect(item.values[.file(.whereFrom)] == .list(["https://example.com/a,b?c=1", "https://example.com/"]))
        #expect(item.spec(for: .file(.whereFrom))?.kind == .lines)
    }

    // MARK: Localization

    @Test func translationsAreComplete() throws {
        // Every English string the sources pass to tr(), and every field label, must be translated.
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MetaEdit")
        let regex = try NSRegularExpression(pattern: #"\btr\("((?:[^"\\]|\\.)*)""#)
        var keys = Set<String>()
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let file as URL in files where file.pathExtension == "swift" && !file.path.contains("/Localization/Translations") {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { keys.insert(String(text[range])) }
            }
        }
        let fields: [any FieldDefinition] = GeneralField.allCases + FileField.allCases + TagLibField.allCases + ImageField.allCases
        for field in fields {
            for category in MediaCategory.allCases { keys.insert(field.label(for: category)) }
        }
        keys.remove("")
        #expect(keys.count > 150)
        for language in [AppLanguage.ru, .es, .zhHans] {
            let table = Translations.strings[language] ?? [:]
            let missing = keys.subtracting(table.keys).sorted()
            #expect(missing.isEmpty, "\(language.rawValue) misses \(missing)")
            let unused = Set(table.keys).subtracting(keys).sorted()
            #expect(unused.isEmpty, "\(language.rawValue) has unused \(unused)")
            for (english, translated) in table {
                let specifiers = { (s: String) in s.matches(of: #/%[@d]/#).map { String($0.output) } }
                #expect(specifiers(english) == specifiers(translated), "\(language.rawValue): \(english)")
            }
        }
        let pluralKeys = Set(Translations.enPlurals.keys)
        let formCounts: [AppLanguage: Int] = [.en: 2, .ru: 3, .es: 2, .zhHans: 1]
        for (language, count) in formCounts {
            let table = Translations.plurals[language] ?? [:]
            #expect(Set(table.keys) == pluralKeys, Comment(rawValue: language.rawValue))
            #expect(table.values.allSatisfy { $0.count == count }, Comment(rawValue: language.rawValue))
        }
    }

    @Test func languagesMatchInfoPlist() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any]
        #expect(info?["CFBundleLocalizations"] as? [String] == AppLanguage.supported.map(\.rawValue))
    }

    @Test func shortcutSymbols() {
        #expect(Shortcut.open.symbols == "⌘O")
        #expect(Shortcut.saveAll.symbols == "⇧⌘S")
        #expect(Shortcut.deselectAll.symbols == "⌥⇧⌘A")
        #expect(Shortcut.removeFromList.symbols == "⌘⌫")
    }

    @Test func russianPluralRules() {
        let expected: [(Int, Int)] = [(1, 0), (2, 1), (4, 1), (5, 2), (11, 2), (12, 2), (14, 2), (21, 0), (22, 1), (25, 2), (111, 2), (101, 0)]
        for (n, index) in expected {
            #expect(Localizer.pluralIndex(n, .ru) == index, "\(n)")
        }
        #expect(Localizer.pluralIndex(1, .en) == 0)
        #expect(Localizer.pluralIndex(0, .en) == 1)
        #expect(Localizer.pluralIndex(7, .zhHans) == 0)
    }

    // MARK: Batch editing

    @Test func batchMixedValuesAndOnlyWhereEmpty() async throws {
        let a = load(try copy("sample.mp3"))
        let b = load(try copy("sample.flac"))
        let title = FieldKey.general(.title)
        let genre = FieldKey.general(.genre)

        func field(_ key: FieldKey) -> FieldState {
            SelectionFields.compute([a, b]).flatMap(\.fields).first { $0.id == key }!
        }
        #expect(field(title).isMixed)
        #expect(field(genre).isMixed)
        #expect(field(genre).mixedValues.count == 2)
        #expect(SelectionFields.compute([a, b]).flatMap(\.fields).first { $0.id == FileField.name.key } == nil)

        let state = AppState()
        state.stage(.text("Rock"), for: genre, in: [a, b])
        #expect(field(genre).pending == .uniform(.text("Rock")))
        #expect(!(field(genre).isMixed))

        await state.performSave([a, b], onlyWhereEmpty: [genre]).value
        #expect(a.values[genre] == .text("Test"))
        #expect(b.values[genre] == .text("Rock"))
        #expect(!(a.isDirty))
        #expect(!(b.isDirty))

        state.stage(.text("Same"), for: title, in: [a, b])
        await state.performSave([a, b], onlyWhereEmpty: []).value
        #expect(field(title).original == .same(.text("Same")))
    }

    // MARK: Covers

    @Test func loadedCoverKeepsOnlyAThumbnail() async throws {
        let url = try copy("sample.mp3")
        let jpeg = try largeCover()
        let item = load(url)
        item.stage(picked(jpeg), for: .general(.cover))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])

        guard case .picture(let picture)? = item.values[.general(.cover)] else {
            Issue.record("cover missing after save")
            return
        }
        guard case .file(let source) = picture.source else {
            Issue.record("a loaded cover must not keep its bytes")
            return
        }
        #expect(source == url)
        #expect(picture.byteCount == jpeg.count)
        #expect(picture.mimeType == "image/jpeg")
        #expect(picture.pixelWidth == 1200 && picture.pixelHeight == 1200)
        let thumbnail = try #require(picture.thumbnail)
        let thumbnailSource = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let size = CGImageSourceCopyPropertiesAtIndex(thumbnailSource, 0, nil) as? [CFString: Any]
        let longSide = max(size?[kCGImagePropertyPixelWidth] as? Int ?? 0, size?[kCGImagePropertyPixelHeight] as? Int ?? 0)
        #expect(longSide == Picture.thumbnailPixelSize)
        #expect(thumbnail.count * 4 < jpeg.count)
        // The bytes are read back from the file on demand.
        #expect(try picture.bytes() == jpeg)
    }

    @Test func coverCopiedFromAnotherFile() async throws {
        let cover = try Data(contentsOf: Self.fixtures.appendingPathComponent("sample.png"))
        let source = load(try copy("sample.mp3"))
        source.stage(picked(cover), for: .general(.cover))
        try await source.save(preserveModificationDate: true, onlyWhereEmpty: [])
        let fromFile = try #require(source.values[.general(.cover)])

        // Picking another file's cover in the "values differ" popover stages a picture without bytes.
        let target = load(try copy("sample.flac"))
        target.stage(fromFile, for: .general(.cover))
        try await target.save(preserveModificationDate: true, onlyWhereEmpty: [])
        #expect(target.error == nil)
        guard case .picture(let written)? = target.values[.general(.cover)] else {
            Issue.record("cover missing after save")
            return
        }
        #expect(try written.bytes() == cover)
    }

    @Test func coverChangedOnDiskIsNotCopied() async throws {
        let first = try Data(contentsOf: Self.fixtures.appendingPathComponent("sample.png"))
        let second = try Data(contentsOf: Self.fixtures.appendingPathComponent("sample.jpg"))
        let item = load(try copy("sample.mp3"))
        item.stage(picked(first), for: .general(.cover))
        try await item.save(preserveModificationDate: true, onlyWhereEmpty: [])
        guard case .picture(let loaded)? = item.values[.general(.cover)] else {
            Issue.record("cover missing after save")
            return
        }
        // Another app replaces the cover behind the editor's back.
        _ = try ProviderRegistry.tagLib.write(url: item.url, changes: [.general(.cover): picked(second)])
        #expect(throws: MetadataError.self) { try loaded.bytes() }
    }

    @Test func manyCoversStayOutOfMemory() async throws {
        let cover = try largeCover()
        let folder = tempDir.appendingPathComponent("album")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let template = load(try copy("sample.mp3"))
        template.stage(picked(cover), for: .general(.cover))
        try await template.save(preserveModificationDate: true, onlyWhereEmpty: [])
        for index in 0..<20 {
            try FileManager.default.copyItem(at: template.url, to: folder.appendingPathComponent("track\(index).mp3"))
        }

        let state = AppState()
        await state.addURLs([folder]).value
        #expect(state.files.count == 20)
        for file in state.files {
            guard case .picture(let picture)? = file.values[.general(.cover)] else {
                Issue.record("\(file.name): cover missing")
                continue
            }
            if case .bytes = picture.source {
                Issue.record("\(file.name): the cover's bytes are kept in memory")
            }
            #expect((picture.thumbnail?.count ?? .max) * 4 < cover.count, Comment(rawValue: file.name))
        }
        // The same cover in every file is one value, so the selection shows it as uniform.
        let field = SelectionFields.compute(state.files).flatMap(\.fields).first { $0.id == .general(.cover) }
        #expect(field?.isMixed == false)
    }

    // MARK: Adding files

    @Test func overlappingAddsDoNotDuplicate() async throws {
        let mp3 = try copy("sample.mp3")
        let flac = try copy("sample.flac")
        let state = AppState()
        let first = state.addURLs([mp3, flac])
        let second = state.addURLs([tempDir])
        #expect(state.isLoading)
        await first.value
        await second.value
        #expect(!state.isLoading)
        #expect(state.files.count == 2)
        #expect(Set(state.files.map(\.name)) == ["sample.mp3", "sample.flac"])
    }

    @Test func concurrentMapKeepsOrder() async {
        let items = Array(0..<40)
        var received: [Int] = []
        // Later items finish first, so results arrive out of order.
        await mapConcurrently(items, width: 8, transform: { item in
            usleep(useconds_t((40 - item) * 200))
            return item * 2
        }) { item, output in
            #expect(output == item * 2)
            received.append(item)
        }
        #expect(received == items)
    }

    @Test func loadsManyFilesInOrder() async throws {
        let folder = tempDir.appendingPathComponent("many")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let samples = ["sample.mp3", "sample.flac", "sample.m4a", "sample.jpg"]
        var names: [String] = []
        for index in 0..<12 {
            for sample in samples {
                let name = String(format: "%02d-", index) + sample
                try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(sample), to: folder.appendingPathComponent(name))
                names.append(name)
            }
        }
        let state = AppState()
        await state.addURLs([folder]).value
        #expect(state.files.map(\.name) == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        for file in state.files {
            #expect(file.error == nil, Comment(rawValue: file.name))
            if file.name.hasSuffix("mp3") {
                #expect(file.values[.general(.title)] == .text("Sine MP3"))
            }
        }
    }
}
