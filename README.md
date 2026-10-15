# MetaEdit: free metadata editor for Mac (music, photo, video and any file)

**MetaEdit** is a free, open-source metadata editor and tag editor for macOS. Open any file, see all of its
metadata, change it and save. Edit MP3 tags, FLAC and M4A tags, album covers, photo EXIF, IPTC and XMP,
video tags and Finder tags in one simple app. Select many files and edit them all at once.

The file itself is never re-encoded or recompressed. Only the metadata changes: the audio, the video and the
pixels stay exactly the same.

[**Download for macOS**](https://github.com/j-tap/meta-edit/releases/latest) · [Русская версия](README.ru.md)

![MetaEdit batch editing three MP3 files: shared values are shown, differing values say "Multiple values"](docs/images/batch-editing.png)

## Features

- **One app for every file type.** Music, photos, video, documents and plain files. Unknown files still get
  their name, dates, Finder tags and Finder comment.
- **Batch metadata editing.** Select a whole album and set the genre, artist or cover for every track in one go.
  Fields that differ show "Multiple values", and you can pick one of the existing values to apply everywhere.
- **Confirmation before changing many files.** You see exactly which fields change in how many files.
  The "Only where empty" option fills gaps without overwriting what is already there.
- **Lossless.** Tags are rewritten in place. Media streams and image data are copied byte for byte.
- **Keeps what it does not understand.** Unknown tags, camera data, colour profiles and IPTC stay in the file.
- **All tags view.** Besides the common fields, every raw tag of the file is listed and editable.
- **Cover art.** View, replace, remove and export embedded album artwork.
- **Keeps the modification date** of the file when saving, if you want it to.
- **Native and small.** Written in Swift and SwiftUI, about 5 MB, no runtime to install.

## Supported formats

| Kind | Formats | What you can edit |
|---|---|---|
| Audio | MP3, FLAC, OGG Vorbis, Opus, M4A (AAC, ALAC), WAV, AIFF, APE, WavPack, Musepack, WMA, DSF, DFF | title, artist, album, album artist, year, genre, track, disc, composer, comment, lyrics, BPM, ISRC, cover art and any raw tag (ID3v2, Vorbis comments, MP4 atoms, APE, ASF) |
| Video | MP4, M4V, MKV, WebM | title, artist, description, comment, genre, cover and other tags |
| Images | JPEG, PNG, TIFF, HEIC, AVIF, GIF, JPEG 2000, PSD (WebP and camera RAW read-only) | title, creator, description, keywords, copyright, rating, headline, credit, city, country, label and any XMP tag; EXIF camera data is shown |
| Any file | everything | file name, Finder tags with colours, Finder comment, "Where from", created and modified dates |

Coming next: PDF and Office documents, optional [ExifTool](https://exiftool.org) integration for camera RAW,
MOV and exotic formats, and versions for Windows and Linux.

## Install

1. Download the `.dmg` from the [latest release](https://github.com/j-tap/meta-edit/releases/latest).
2. Open it and drag **MetaEdit** to **Applications**.
3. The app is not notarized by Apple yet, so macOS blocks the first launch. Open it once, then go to
   **System Settings → Privacy & Security** and click **Open Anyway**. Or run in Terminal:

   ```
   xattr -dr com.apple.quarantine /Applications/MetaEdit.app
   ```

Requires macOS 14 Sonoma or newer, Apple Silicon or Intel.

## How to use

1. Drag files or folders into the window, or press ⌘O. Folders are added with all subfolders.
2. Select one file to edit it, or several files (⇧⌘A selects all) to edit them together.
3. Change the fields. Changed files get an orange dot.
4. Press ⌘S to save the selection, or ⇧⌘S to save every changed file.

## FAQ

**How do I edit MP3 tags on a Mac?**
Drop the MP3 files into MetaEdit, change title, artist, album or genre, and press ⌘S. ID3v2 tags are written,
the audio is not touched.

**How do I change the genre or cover of a whole album at once?**
Add the album folder, select all tracks, type the genre or drop an image on the cover, save and confirm.

**How do I edit photo metadata (EXIF, IPTC, XMP) on a Mac?**
Open the photo, edit title, description, keywords, copyright or location fields and save. The image is not
recompressed, so there is no quality loss.

**Will editing tags reduce quality?**
No. MetaEdit never re-encodes audio, video or images. Automated tests compare the decoded audio and the image
pixels before and after every write.

**Is it free?**
Yes. MetaEdit is free and open source under the MIT license.

## Alternatives

Good tools exist for single file types: MusicBrainz Picard, Kid3 and Mp3tag for music, ExifTool and its GUIs
for photos, Media Meta as a paid app. MetaEdit aims to be one simple, free app for all of them, with careful
batch editing.

## Build from source

```
git clone https://github.com/j-tap/meta-edit.git
cd meta-edit
brew install cmake
make macos            # builds apps/macos/dist/MetaEdit.app
make test-macos       # runs the test suite
```

Xcode Command Line Tools are enough, Xcode itself is not required. Details are in
[apps/macos/README.md](apps/macos/README.md).

## Project layout

One repository holds a native app per platform and a shared specification:

| Platform | Stack | Status |
|---|---|---|
| macOS 14+ | Swift, SwiftUI, TagLib, ImageIO | available |
| Windows 10/11 | C#, .NET, WPF, TagLib# | planned |
| Linux | Python, GTK 4, libadwaita, mutagen, GExiv2 | planned |

- [Architecture and release process](docs/architecture.md)
- [Metadata fields and format mappings](docs/metadata-schema.md)
- [Batch editing rules](docs/batch-editing.md)

## Contributing

Bug reports, format requests and pull requests are welcome in
[Issues](https://github.com/j-tap/meta-edit/issues).

## License

[MIT](LICENSE). Free to use, change and share, keeping the copyright notice.
