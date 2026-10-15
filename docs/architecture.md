# Architecture

## Goals

- Edit metadata of any file: audio, video, images, documents, plain files.
- Never touch the payload. Only metadata blocks are rewritten; the media stream, the pixels and the document
  content stay byte for byte identical.
- Small, fast, native on every platform.
- One list of files on the left, one editor on the right, batch editing across a selection.

## One repository, three native apps

Native per-platform apps were chosen over a single cross-platform shell. The UI is the simple part of this
program. The hard part is the metadata logic, and that part is specified once in `docs/` and implemented three
times with the best library for each platform.

| Platform | Language and UI | Audio and MP4 tags | Image metadata | File attributes | Directory |
|---|---|---|---|---|---|
| macOS 14+ | Swift 6, SwiftUI | TagLib 2, static, C API | ImageIO, lossless copy with new metadata | URLResourceValues, extended attributes | `apps/macos` |
| Windows 10/11 | C#, .NET 10, WPF with Fluent theme | TagLib# | TagLib# for JPEG, TIFF, PNG; Windows Property System | Windows Property System, NTFS alternate streams | `apps/windows` |
| Linux, GNOME first | Python 3.11+, GTK 4, libadwaita | mutagen | GExiv2 | extended attributes `user.xdg.*` | `apps/linux` |

ExifTool is an optional add-on on every platform. When it is found on the system, the app routes formats it
cannot handle natively (camera RAW, MOV, PDF, HEIF video, anything exotic) through it and exposes every tag
ExifTool knows. It is never bundled.

Why these choices:

- macOS: Apple has no API to write ID3, FLAC or Vorbis tags, so TagLib is required. Everything else is covered
  by system frameworks, which keeps the app around ten megabytes with no runtime dependencies.
- Windows: WPF is the stable native toolkit; with the Fluent theme of .NET 9+ it follows the Windows 11 look in
  light and dark. WinUI 3 was considered and rejected for tooling churn. TagLib# is the most complete single
  .NET library, and the non-UI part builds and tests on any OS, so it can be developed on macOS.
- Linux: GTK 4 with libadwaita is the native GNOME look. Python is an officially supported GNOME language,
  mutagen is the strongest audio tagging library available, GExiv2 is the GNOME binding of Exiv2. No
  compilation, straightforward Flatpak and Debian packaging. Rust with gtk4-rs was considered; Python was
  chosen for simplicity.

## Shared specification

The three apps implement the same documents:

- `docs/metadata-schema.md`: field groups, normalized keys, per-format mapping tables, write rules.
- `docs/batch-editing.md`: selection model, mixed values, confirmation and save rules.

## Layout

```
apps/macos/     Swift package, TagLib build script, app bundle and DMG scripts
apps/windows/   .NET solution: MetaEdit.Core (portable), MetaEdit.Wpf (UI)
apps/linux/     Python package, Flatpak manifest, Debian packaging
docs/           shared specification
scripts/        release tooling
VERSION         single version for all three apps
Makefile        entry points: make macos | windows | linux | release
```

## Versioning and releases

`VERSION` holds the semantic version used by all three apps. A release is one command:

```
make release V=1.2.0
```

`scripts/release.sh` checks that the tree is clean and on `main`, writes `VERSION`, commits `Release 1.2.0`,
tags `v1.2.0` and pushes. GitHub Actions (`.github/workflows/release.yml`) reacts to the tag:

1. `macos-latest` builds TagLib and the Swift app, signs it ad hoc and produces `MetaEdit-1.2.0-macos.dmg`.
2. `windows-latest` publishes a self-contained x64 build: `MetaEdit-1.2.0-windows-x64.zip`.
3. `ubuntu-latest` builds `MetaEdit-1.2.0-linux-amd64.deb` and `MetaEdit-1.2.0.flatpak`.
4. A final job creates the GitHub Release `v1.2.0` and attaches every artifact.

`ci.yml` runs the same builds plus tests on every push and pull request without publishing. The macOS job builds the
app with Xcode on the GitHub runner, so the SwiftUI code is verified there even on machines with only the Command Line Tools.

Local builds: `make macos` on macOS, `make linux` on Linux (or on macOS with Homebrew GTK for development),
`make windows` on Windows. The Windows core library and its tests run everywhere with `dotnet test`.
