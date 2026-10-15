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
- Editor with the groups from `docs/metadata-schema.md`: General, Audio, Photo, File, Technical, All tags.
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
- SwiftPM under the Command Line Tools does not reliably pick a test library; `scripts/test.sh` passes
  `--enable-swift-testing --disable-xctest`.
- ImageIO writes an XMP packet only when the metadata carries an `iio:hasXMP` marker; the provider adds it.
  ImageIO also regenerates the IPTC IIM block from XMP and Exif on write, so IPTC-only values are mirrored
  into XMP before writing. When Exif and IPTC disagree, Exif wins, as in the Metadata Working Group rules.
- The setter of `URLResourceValues.tagNames` needs macOS 26, so Finder tags are written as the
  `com.apple.metadata:_kMDItemUserTags` attribute, preserving tag colours.

## Layout

```
Package.swift            SwiftPM manifest: CTagLib system library, MetaEdit executable, tests
Sources/CTagLib/         module map for the TagLib C API
Sources/MetaEdit/        App, Model, Providers, Views, Support
Tests/MetaEditTests/     Swift Testing suite and generated fixtures
Resources/               Info.plist, AppIcon.icns
scripts/                 build-taglib, build-app, make-dmg, make-icon, make-samples, test
vendor/                  TagLib build output, not committed
```
