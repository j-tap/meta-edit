# Metadata schema

This document defines what every MetaEdit app shows and writes. The three apps implement it with
different libraries; the behaviour must be the same. A change in behaviour starts here.

## Field model

A file is described by a list of fields. Each field has:

- `key`: stable identifier in lower camel case (`title`, `albumArtist`, `whereFrom`).
- `group`: the editor section that shows it (see below).
- `kind`: `text`, `multiline`, `integer`, `boolean`, `date`, `list` (ordered strings, edited comma separated),
  `lines` (ordered strings edited one per line, for items that may contain commas, such as URLs), `image` (bytes plus MIME type).
- `writable`: whether the provider can write it back. Read-only fields live in the Technical group.
- `value`: present or absent. Absent means "no such tag in the file". An empty string is never stored:
  saving an empty field removes the tag.

Fields come from providers. A provider owns one metadata container: ID3v2, Vorbis comments, MP4 atoms,
Exif/IPTC/XMP, PDF Info, filesystem attributes. Several providers can serve one file: a JPEG gets
`image` + `file`, an MP3 gets `audio` + `file`.

## Groups

| Group | Title in UI | Contents |
|---|---|---|
| `general` | General | Normalized fields that exist in most containers, mapped per format below. |
| `audio` | Audio | Audio-only fields: lyrics, BPM, publisher, ISRC, compilation, grouping. |
| `photo` | Photo | Exif / IPTC / XMP fields: headline, credit, location, GPS, rating, label, date taken. |
| `video` | Video | QuickTime / MP4 fields: show, episode, long description, location, creation date. |
| `document` | Document | PDF Info, Office core properties, EPUB OPF. |
| `file` | File | Filesystem attributes available for any file. |
| `technical` | Technical | Read-only facts: duration, bitrate, codec, dimensions, camera, page count, size, type. |
| `raw` | All tags | Every tag of every container as the library sees it: ID3 frame ids, Vorbis keys, MP4 atoms, Exif/XMP names. Arbitrary tags can be added and removed here. |

The editor shows General, then the format groups that apply, then File, then Technical and All tags collapsed.

## Fields per file type

A file belongs to one category, decided by its type: audio, video, image or other. The category decides which
General fields and which format groups the file gets, and how some General fields are labelled. A tag that the
category does not offer is still shown and editable in All tags.

| Category | Files | General fields | Groups |
|---|---|---|---|
| audio | MP3, FLAC, OGG, Opus, M4A, WAV, AIFF, APE, WMA, MKA, ... | title, artist, album, albumArtist, date, genre, track, disc, composer, comment, copyright, cover | Audio |
| video | MP4, M4V, 3GP, MKV, WebM | title, artist, date, genre, comment, description, copyright, cover | Video (MP4 family only) |
| image | everything ImageIO / Exiv2 / the platform reads | title, artist, date, description, keywords, copyright, rating | Photo |
| other | anything else | none | |

Every category gets the File group, Technical and All tags.

Labels that depend on the category:

| key | audio | video | image |
|---|---|---|---|
| artist | Artist | Author | Author |
| date | Year | Date | Date created |

General fields keep one key across categories, so a selection of an MP3 and a JPEG still edits one row. When
the selected files label a field differently, the row shows the labels joined with " / ", e.g. "Artist / Author".

## General fields and per-format mapping

An empty cell means the format has no standard place for the field; the field is not offered for such files.

| key | kind | ID3v2 | Vorbis (FLAC, OGG, Opus) | MP4 / M4A / M4V | APEv2 | RIFF INFO (WAV, AVI) | ASF (WMA) | Images: Exif / IPTC / XMP | PDF Info / XMP |
|---|---|---|---|---|---|---|---|---|---|
| title | text | TIT2 | TITLE | ©nam | Title | INAM | Title | dc:title; IPTC ObjectName | Title; dc:title |
| artist | text | TPE1 | ARTIST | ©ART | Artist | IART | Author | Exif Artist; dc:creator; IPTC By-line | Author; dc:creator |
| albumArtist | text | TPE2 | ALBUMARTIST | aART | Album Artist | | WM/AlbumArtist | | |
| album | text | TALB | ALBUM | ©alb | Album | IPRD | WM/AlbumTitle | | |
| date | text | TDRC (2.4) / TYER (2.3) | DATE | ©day | Year | ICRD | WM/Year | Exif DateTimeOriginal; photoshop:DateCreated; IPTC DateCreated | CreationDate; xmp:CreateDate |
| genre | text | TCON | GENRE | ©gen | Genre | IGNR | WM/Genre | | |
| track | text, `n` or `n/total` | TRCK | TRACKNUMBER + TRACKTOTAL | trkn | Track | ITRK | WM/TrackNumber | | |
| disc | text, `n` or `n/total` | TPOS | DISCNUMBER + DISCTOTAL | disk | Disc | | WM/PartOfSet | | |
| composer | text | TCOM | COMPOSER | ©wrt | Composer | IMUS | WM/Composer | | |
| comment | multiline | COMM | COMMENT | ©cmt | Comment | ICMT | Description | Exif UserComment | |
| description | multiline | | DESCRIPTION | desc | | ISBJ | | dc:description; IPTC Caption-Abstract; Exif ImageDescription | Subject; dc:description |
| keywords | list | TXXX:KEYWORDS | KEYWORDS | keyw | Keywords | IKEY | WM/Category | IPTC Keywords; dc:subject | Keywords; dc:subject |
| copyright | text | TCOP | COPYRIGHT | cprt | Copyright | ICOP | Copyright | Exif Copyright; dc:rights; IPTC CopyrightNotice | dc:rights |
| rating | integer 0..5 | POPM | RATING | | | | WM/SharedUserRating | xmp:Rating | |
| cover | image | APIC | METADATA_BLOCK_PICTURE | covr | Cover Art (Front) | | WM/Picture | | |

Notes:

- Libraries with a unified property map (TagLib, mutagen Easy interfaces) already do most of this mapping.
  The table is the contract for what the user sees, whatever the library does underneath.
- `date` is free text. Audio formats store a year or ISO date; Exif stores `YYYY:MM:DD HH:MM:SS`, XMP stores
  ISO 8601. The provider converts between the user-facing ISO form and the storage form.
- `rating`: POPM stores 0..255, mapped to stars with the common thresholds (1 = 1..63, 2 = 64..127, 3 = 128..195,
  4 = 196..254, 5 = 255). WM/SharedUserRating stores 0..99.
- `track` and `disc` are shown as entered. The provider splits `n/total` into separate tags where the format wants that.
- Where Exif, IPTC and XMP carry the same field, writing updates all of them; reading prefers XMP, then IPTC, then Exif.

## Audio group

| key | kind | ID3v2 | Vorbis | MP4 | APEv2 | ASF |
|---|---|---|---|---|---|---|
| lyrics | multiline | USLT | LYRICS | ©lyr | Lyrics | WM/Lyrics |
| bpm | integer | TBPM | BPM | tmpo | BPM | WM/BeatsPerMinute |
| publisher | text | TPUB | ORGANIZATION | ----:com.apple.iTunes:LABEL | Publisher | WM/Publisher |
| isrc | text | TSRC | ISRC | ----:com.apple.iTunes:ISRC | ISRC | WM/ISRC |
| encodedBy | text | TENC | ENCODEDBY | ©too (read-only) | EncodedBy | WM/EncodedBy |
| compilation | boolean | TCMP | COMPILATION | cpil | Compilation | WM/IsCompilation |
| grouping | text | GRP1, TIT1 | GROUPING | ©grp | Grouping | WM/ContentGroupDescription |

## Photo group (images)

| key | kind | Exif | IPTC IIM | XMP |
|---|---|---|---|---|
| headline | text | | Headline (2:105) | photoshop:Headline |
| credit | text | | Credit (2:110) | photoshop:Credit |
| source | text | | Source (2:115) | photoshop:Source |
| city | text | | City (2:90) | photoshop:City |
| state | text | | Province-State (2:95) | photoshop:State |
| country | text | | Country-PrimaryLocationName (2:101) | photoshop:Country |
| label | text | | | xmp:Label |
| dateTaken | date | DateTimeOriginal + SubSecTimeOriginal | DateCreated + TimeCreated | photoshop:DateCreated |
| software | text | Software | | xmp:CreatorTool |
| userComment | multiline | UserComment | | exif:UserComment |
| gpsLatitude | text, decimal degrees | GPSLatitude + GPSLatitudeRef | | exif:GPSLatitude |
| gpsLongitude | text, decimal degrees | GPSLongitude + GPSLongitudeRef | | exif:GPSLongitude |
| gpsAltitude | text, metres | GPSAltitude + GPSAltitudeRef | | exif:GPSAltitude |
| orientation | integer 1..8 | Orientation | | tiff:Orientation |

Camera make, model, lens, exposure, ISO, focal length, dimensions and colour profile are shown read-only in
Technical. They stay editable in All tags.

## Video group (MP4, M4V, MOV, 3GP)

The General `description` of an MP4 video is the `desc` atom (TagLib calls it PODCASTDESC); Matroska uses DESCRIPTION.

| key | kind | MP4 ilst | QuickTime keys / udta |
|---|---|---|---|
| show | text | tvsh | |
| season | integer | tvsn | |
| episode | integer | tves | |
| episodeId | text | tven | |
| network | text | tvnn | |
| longDescription | multiline | ldes (planned) | com.apple.quicktime.description |
| mediaKind | text | stik (planned) | |
| location | text, ISO 6709 | | ©xyz; com.apple.quicktime.location.ISO6709 |
| creationDate | date | | com.apple.quicktime.creationdate |
| cameraMake | text | | com.apple.quicktime.make |
| cameraModel | text | | com.apple.quicktime.model |

MKV is read-only until a Matroska writer is available on the platform (mkvpropedit when installed).

## Document group

| key | kind | PDF Info | XMP | Office core.xml | EPUB OPF |
|---|---|---|---|---|---|
| title | text | Title | dc:title | dc:title | dc:title |
| author | text | Author | dc:creator | dc:creator | dc:creator |
| subject | text | Subject | dc:description | dc:subject | dc:description |
| keywords | list | Keywords | pdf:Keywords; dc:subject | cp:keywords | dc:subject |
| creatorTool | text | Creator | xmp:CreatorTool | | |
| producer | text, read-only | Producer | pdf:Producer | | |
| created | date | CreationDate | xmp:CreateDate | dcterms:created | |
| modified | date | ModDate | xmp:ModifyDate | dcterms:modified | dcterms:modified |
| language | text | | dc:language | dc:language | dc:language |
| publisher | text | | | | dc:publisher |
| identifier | text | | | | dc:identifier |

Document providers come after audio, images and video. Markdown front matter (title, date, tags) is a
candidate for a later provider.

## File group (every file)

| key | kind | macOS | Linux | Windows |
|---|---|---|---|---|
| name | text | rename | rename | rename |
| created | date | creationDate | not writable on most filesystems | creation time |
| modified | date | contentModificationDate | mtime | last write time |
| tags | list | Finder tags, `com.apple.metadata:_kMDItemUserTags` | `user.xdg.tags` | |
| comment | multiline | Finder comment, `com.apple.metadata:kMDItemFinderComment` | `user.xdg.comment` | |
| whereFrom | lines | `com.apple.metadata:kMDItemWhereFroms`, shown by Finder as "Where from" | `user.xdg.origin.url` | `Zone.Identifier` stream, HostUrl |

`name` is only editable with a single file selected. Technical shows path, size and type.

## Write rules

1. Never re-encode or recompress. Only metadata blocks are rewritten; the payload is copied byte for byte or left in place.
2. Preserve what is not understood: unknown tags, other containers in the same file, resource forks, extended attributes.
3. The modification time is restored after a write unless the user turned off "Preserve modification date".
   The `created` and `modified` fields edited explicitly are the exception.
4. An empty value removes the tag. Lists are written in order; an empty list removes the tag.
5. MP3: write ID3v2.4 with UTF-8 by default; a setting offers ID3v2.3 with UTF-16 for old players and Windows Explorer.
   ID3v1, when present, is kept in sync.
6. Images: write XMP and Exif together; keep IPTC IIM in sync when the platform library can; never drop the ICC profile or the thumbnail.
7. Write to a temporary file in the same directory and replace atomically when the library does not edit in place;
   carry over extended attributes, permissions and creation date.
8. After a write, re-read the file and show what is actually stored.
9. Any error leaves the original file untouched and is reported per file; other files in the batch continue.
