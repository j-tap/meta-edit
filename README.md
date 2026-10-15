# MeteEdit

A simple metadata editor for any file: music, video, images, documents and plain files.
Open a file or a whole folder, see every metadata field, edit it, save. The file itself is never
re-encoded, recompressed or otherwise touched: only its metadata changes.

One repository, three native apps:

| Platform | Stack | Status |
|---|---|---|
| macOS 14+ | Swift, SwiftUI, TagLib, ImageIO | in development |
| Windows 10/11 | C#, .NET, WPF, TagLib# | planned |
| Linux | Python, GTK 4, libadwaita, mutagen, GExiv2 | planned |

Builds for every platform are attached to each [release](../../releases).

## What it does

- File list on the left, editor on the right. Drag files or folders in, or use Open With from the file manager.
- Common fields (title, artist, album, year, genre, comment, keywords, copyright, cover and more) plus the
  full raw tag list of the container: ID3v2, Vorbis comments, MP4 atoms, Exif, IPTC, XMP, QuickTime, PDF Info.
- File-level attributes for any file type: name, dates, tags, comment, "where from".
- Batch editing: select several files, fields that match are shown as usual, fields that differ say so.
  Type a value and it applies to the whole selection after one confirmation.
- Optional [ExifTool](https://exiftool.org) integration: when installed, exotic formats and every tag ExifTool knows become available.

## Documentation

- [Architecture and release process](docs/architecture.md)
- [Metadata schema and format mappings](docs/metadata-schema.md)
- [Batch editing rules](docs/batch-editing.md)
- Per-platform build notes: [macOS](apps/macos/README.md), [Windows](apps/windows/README.md), [Linux](apps/linux/README.md)

## Releasing

```
make release V=1.2.0
```

This tags `v1.2.0` and pushes; GitHub Actions builds all three apps and publishes the release with downloadable artifacts.

## License

[MIT](LICENSE)
