#!/usr/bin/env bash
# Generates small sample files of every supported kind for manual testing. Requires ffmpeg.
# Usage: scripts/make-samples.sh <output dir>
set -euo pipefail
out="${1:?output dir}"
mkdir -p "$out"
cd "$out"
a=(-f lavfi -i "sine=frequency=440:duration=1:sample_rate=22050" -y -loglevel error)
ffmpeg "${a[@]}" -metadata title="Sine MP3" -metadata artist="Sample Artist" -metadata album="Samples" -metadata genre="Test" -c:a libmp3lame -b:a 64k sample.mp3
ffmpeg "${a[@]}" -metadata title="Sine FLAC" -metadata artist="Sample Artist" -c:a flac sample.flac
ffmpeg "${a[@]}" -metadata title="Sine OGG" -c:a vorbis -strict experimental -ac 2 sample.ogg
ffmpeg "${a[@]}" -metadata title="Sine Opus" -c:a libopus sample.opus
ffmpeg "${a[@]}" -metadata title="Sine M4A" -c:a aac sample.m4a
ffmpeg "${a[@]}" -c:a pcm_s16le sample.wav
ffmpeg "${a[@]}" -c:a pcm_s16be sample.aiff
v=(-f lavfi -i "testsrc=duration=1:size=96x64:rate=10" -y -loglevel error)
ffmpeg "${v[@]}" -metadata title="Test MP4" -c:v libx264 -pix_fmt yuv420p sample.mp4
ffmpeg "${v[@]}" -metadata title="Test MOV" -c:v libx264 -pix_fmt yuv420p sample.mov
ffmpeg "${v[@]}" -metadata title="Test MKV" -c:v libx264 -pix_fmt yuv420p sample.mkv
ffmpeg -f lavfi -i "color=c=steelblue:s=96x64" -frames:v 1 -y -loglevel error sample.jpg
ffmpeg -f lavfi -i "color=c=seagreen:s=96x64" -frames:v 1 -y -loglevel error sample.png
ffmpeg -f lavfi -i "color=c=tomato:s=96x64" -frames:v 1 -pix_fmt rgb24 -y -loglevel error sample.tiff
sips -s format heic sample.png --out sample.heic >/dev/null
sips -s format pdf sample.png --out sample.pdf >/dev/null
printf 'Plain text sample.\n' > sample.txt
if command -v exiftool >/dev/null 2>&1; then
  # A JPEG with Exif, IPTC IIM and XMP, for checking that nothing is lost on write.
  exiftool -q -Make=Canon -Model="EOS R5" -LensModel="RF 50mm" -ExposureTime=1/200 -FNumber=2.8 -ISO=100 \
    -FocalLength=50 -DateTimeOriginal="2023:04:05 06:07:08" -GPSLatitude=52.52 -GPSLatitudeRef=N -GPSLongitude=13.405 -GPSLongitudeRef=E \
    -Artist="Jane Doe" -Copyright="(c) Jane" -ImageDescription="Exif description" -UserComment="Exif comment" -SerialNumber=ABC123 \
    -IPTC:Keywords=iptc1 -IPTC:Keywords=iptc2 -IPTC:Headline="IPTC headline" -IPTC:Credit="IPTC credit" -IPTC:City=Paris \
    -IPTC:ObjectName="IPTC title" -IPTC:Caption-Abstract="IPTC caption" -IPTC:Source="IPTC source" \
    -XMP-xmp:Label=Green -XMP-xmpMM:DocumentID="xmp.did:1234" -XMP-crs:WhiteBalance="As Shot" -o rich.jpg sample.jpg
fi
ls -la "$out"
