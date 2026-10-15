# MetaEdit — free metadata and tag editor for Mac

MetaEdit edits metadata of almost any file on macOS: MP3, FLAC and M4A tags with album art, photo EXIF, IPTC
and XMP, video tags, Finder tags and comments. One file or a whole folder at once. Files are never re-encoded,
only the tags change.

[**Download for macOS**](https://github.com/j-tap/meta-edit/releases/latest) · macOS 14+, Apple Silicon and Intel · [Русский](README.ru.md)

![MetaEdit batch editing three MP3 files: shared values are shown, differing values say "Multiple values"](docs/images/batch-editing.png)

## Features

- Music, photos, video and everything else in one window. Unknown formats still get name, dates, Finder tags
  and Finder comment.
- Batch editing: select an album and set artist, genre or cover for all tracks. When files have different
  values, the field shows "Multiple values" and lets you pick one for all of them.
- Before saving several files you see what changes and in how many files. "Only where empty" fills in blanks
  and leaves filled fields alone.
- All raw tags of a file are listed and editable, not only the common fields.
- Unknown tags, camera data and colour profiles are preserved.
- Cover art: replace, remove, export.
- Optionally keeps the original modification date.
- Native Swift app, about 5 MB.

Audio, video and image data are copied byte for byte. Tests decode audio and compare pixels before and after
every write to make sure of it.

## Formats

| Type | Formats | Fields |
|---|---|---|
| Audio | MP3, FLAC, OGG Vorbis, Opus, M4A (AAC, ALAC), WAV, AIFF, APE, WavPack, Musepack, WMA, DSF, DFF | title, artist, album, album artist, year, genre, track, disc, composer, comment, lyrics, BPM, ISRC, cover, any raw ID3v2 / Vorbis / MP4 / APE / ASF tag |
| Video | MP4, M4V, MKV, WebM | title, artist, description, comment, genre, cover and more |
| Images | JPEG, PNG, TIFF, HEIC, AVIF, GIF, JPEG 2000, PSD; WebP and RAW read-only | title, creator, description, keywords, copyright, rating, headline, credit, city, country, label, any XMP tag; EXIF is shown |
| Any file | — | name, Finder tags and colours, Finder comment, "Where from", created and modified dates |

Planned: PDF and Office documents, [ExifTool](https://exiftool.org) for RAW, MOV and rare formats, Windows
and Linux versions.

## Install

Download the `.dmg` from [releases](https://github.com/j-tap/meta-edit/releases/latest) and drag MetaEdit
to Applications.

The app isn't notarized yet, so macOS blocks the first launch. Allow it in **System Settings → Privacy &
Security → Open Anyway**, or run:

```
xattr -dr com.apple.quarantine /Applications/MetaEdit.app
```

## Usage

Drop files or folders into the window (or ⌘O), select one or several (⇧⌘A selects all), edit, press ⌘S.
⇧⌘S saves every changed file; changed files are marked with an orange dot.

## Alternatives

Mp3tag, Kid3 and MusicBrainz Picard for music, ExifTool and its GUIs for photos, Media Meta as a paid option.
MetaEdit handles all of these file types in one free app.

## Build

```
git clone https://github.com/j-tap/meta-edit.git
cd meta-edit
brew install cmake
make macos        # apps/macos/dist/MetaEdit.app
make test-macos
```

Command Line Tools are enough, full Xcode isn't needed. More in [apps/macos/README.md](apps/macos/README.md),
[architecture](docs/architecture.md), [metadata fields](docs/metadata-schema.md) and
[batch editing rules](docs/batch-editing.md).

Bug reports and format requests go to [Issues](https://github.com/j-tap/meta-edit/issues).

## License

[MIT](LICENSE)
