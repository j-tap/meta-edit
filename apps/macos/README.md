# MetaEdit for macOS

Native macOS app: Swift and SwiftUI, TagLib for audio and MP4/Matroska tags, ImageIO for image
metadata, resource values and extended attributes for file attributes. Minimum macOS 14.

## Requirements

- Xcode Command Line Tools with Swift 6 (`xcode-select --install`). Xcode itself is not needed.
- CMake (`brew install cmake`) to build TagLib once.
- ffmpeg and exiftool are optional: `scripts/make-samples.sh` uses them to regenerate test fixtures, and the
  tests verify unchanged audio streams through ffmpeg when it is present.

## Build, test, run

```
scripts/build-taglib.sh      # downloads TagLib, builds universal static libraries into vendor/ (once)
scripts/test.sh              # swift test with the flags that make Swift Testing work under the Command Line Tools
scripts/build-app.sh         # swift build, assembles dist/MetaEdit.app with icon and ad hoc signature
scripts/make-dmg.sh          # wraps the app into dist/MetaEdit-<version>-macos.dmg
open dist/MetaEdit.app
```

`ARCHS=native scripts/build-app.sh` builds only the host architecture, which is faster while developing.
From the repository root: `make macos`, `make macos-dmg`, `make test-macos`.

## What is implemented

- File list with multi-selection, filtering, drag and drop of files and folders (recursive), Open With from
  Finder, keyboard removal, dirty and error markers.
- Editor with the groups from `docs/metadata-schema.md`: General, Audio, Photo, Video, File, Technical, All tags.
  Each file gets the fields of its category (audio, video, image, other), as in "Fields per file type".
- Interface in English, Russian, Spanish and Simplified Chinese (`docs/localization.md`): follows the system,
  can be switched in Settings without a restart.
- Batch editing per `docs/batch-editing.md`: "Multiple values" placeholder, a popover listing the distinct
  values that applies one to every file, removal from all files, per-field revert, confirmation sheet with
  "Only where empty" before writing several files.
- Providers:
  - TagLib: MP3, FLAC, OGG, Opus, Speex, M4A/MP4/M4V, WAV, AIFF, APE, Musepack, WavPack, TrueAudio, WMA,
    DSF, DFF, MKV/MKA/WebM, tracker modules. Unified property map, cover art, duration, bitrate, raw tags.
  - ImageIO: JPEG, PNG, TIFF, HEIC, WebP, GIF, BMP and every other format ImageIO can read; writes XMP and
    Exif, keeps IPTC, never re-encodes pixels. RAW formats are read-only.
  - File attributes: name (rename), created and modified dates, Finder tags with colours, Finder comment,
    "where from".
- Preserve modification date on save (setting), Save and Save All, quit guard for unsaved changes.

Not yet: ExifTool integration, PDF and Office documents, Markdown front matter, rename from tags.

## Notes on platform quirks

- The macOS 26+ SDK declares `@State` as a macro whose plugin ships only with Xcode. The app uses
  `@ViewState`, an alias of the `State` property wrapper (`Sources/MetaEdit/Support/ViewState.swift`),
  so it builds with the Command Line Tools too. Behaviour is identical.
- With the Command Line Tools alone, `xcrun` cannot report a platform path, so SwiftPM does not find the
  Testing framework and its macro plugin. `scripts/test.sh` detects that layout and passes the framework,
  plugin and rpath flags explicitly; with Xcode it runs plain `swift test`.
- ImageIO writes an XMP packet only when the metadata carries an `iio:hasXMP` marker; the provider adds it.
  ImageIO also regenerates the IPTC IIM block from XMP and Exif on write, so IPTC-only values are mirrored
  into XMP before writing. When Exif and IPTC disagree, Exif wins, as in the Metadata Working Group rules.
- Interface strings are Swift dictionaries in `Sources/MetaEdit/Localization`, not `.strings` or `.xcstrings`
  files: string catalogs need Xcode to compile, and in-code tables switch language at runtime. English strings
  are the keys. `build-app.sh` adds empty `.lproj` folders and `CFBundleLocalizations` so that the menus macOS
  provides are localized too; picking a language in Settings writes `AppleLanguages` for the app, which those
  menus read at launch. `translationsAreComplete` collects the `tr()` calls in the sources and every field
  label, and fails on a missing or unused key.
- The setter of `URLResourceValues.tagNames` needs macOS 26, so Finder tags are written as the
  `com.apple.metadata:_kMDItemUserTags` attribute, preserving tag colours.

## Layout

```
Package.swift            SwiftPM manifest: CTagLib system library, MetaEdit executable, tests
Sources/CTagLib/         module map for the TagLib C API
Sources/MetaEdit/        App, Model, Providers, Views, Support
Tests/MetaEditTests/     Swift Testing suite and generated fixtures
Resources/               Info.plist, AppIcon.icns
scripts/                 build-taglib, build-app, make-dmg, make-icon, make-samples, test; env.sh shared by them
vendor/                  TagLib build output, not committed
```

## How the code fits together

- Swift 6 language mode with complete concurrency checking. Providers are stateless `Sendable` structs:
  `FileItem.read` runs them off the main thread and returns a `Snapshot`, which `FileItem` applies on the main
  actor. Saves work the same way. `AppState` queues loads and saves (`SerialTaskQueue`) so they never overlap.
  Within a load, files are read several at a time (`mapConcurrently`) and join the list in order.
- A field is identified by `FieldKey`, an enum: `.general` fields are shared between providers, `.file`,
  `.tagLib` and `.image` belong to one provider, and raw tags carry the name their container uses. Labels,
  groups and kinds are defined once in the field enums (`Model/GeneralField.swift`, `Model/ProviderFields.swift`);
  providers only map those fields onto their containers.
- Covers are kept as `Picture`: a thumbnail of at most 256 pixels, the type, the size and a SHA-256 digest.
  The bytes stay in the file and are read again to export a cover or copy it to other files, so a
  selection of thousands of tracks does not hold every cover in memory. Identical covers share one thumbnail.
- `Localizer` is thread safe, since providers translate error messages in the background, and observable, so
  views re-render when the language changes.
- Each build setting has one source. The version is in `VERSION`, the minimum macOS version in the platforms of
  `Package.swift`, and the app name, bundle identifier, icon and languages in `Resources/Info.plist`.
  `scripts/env.sh` reads them for the other scripts, and `build-app.sh` fills the `__VERSION__` and
  `__MIN_MACOS__` placeholders of the Info.plist. Tests check that `AppLanguage` matches the Info.plist languages.
- Keyboard shortcuts are defined once in `Support/Shortcut.swift`; menus and help texts both use them.
