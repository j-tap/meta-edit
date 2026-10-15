# MeteEdit for macOS

Native macOS app: Swift, SwiftUI, TagLib for audio and MP4 tags, ImageIO for image metadata,
URL resource values and extended attributes for file attributes. Minimum macOS 14.

## Requirements

- Xcode Command Line Tools with Swift 6 (`xcode-select --install`). Xcode itself is not needed.
- CMake (`brew install cmake`) to build TagLib once.

## Build

```
scripts/build-taglib.sh   # downloads TagLib, builds universal static libs into vendor/ (once)
scripts/build-app.sh      # swift build, assembles dist/MeteEdit.app, ad hoc signature
open dist/MeteEdit.app
```

`make macos` from the repository root runs both. `scripts/make-dmg.sh` wraps the app into `dist/MeteEdit-<version>-macos.dmg`.

For development, `swift build && swift run` works too; without the bundle the app has no icon, no document
type registration and no Finder integration.

## Layout

```
Package.swift            SwiftPM manifest: CTagLib system library + MeteEdit executable
Sources/CTagLib/         module map for the TagLib C API
Sources/MeteEdit/        app sources: App, Model, Providers, Views, Support
Resources/               Info.plist, icon
scripts/                 build-taglib.sh, build-app.sh, make-dmg.sh
vendor/                  TagLib build output, not committed
```
