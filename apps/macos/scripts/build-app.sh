#!/usr/bin/env bash
# Builds MetaEdit.app into apps/macos/dist. ARCHS=native builds only the host architecture (faster for development).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$here/.." && pwd)"
root="$(cd "$app/../.." && pwd)"
version="$(tr -d '[:space:]' < "$root/VERSION")"
archs="${ARCHS:-universal}"

"$here/build-taglib.sh"

cd "$app"
flags=(-c release)
if [[ "$archs" == "universal" ]]; then
  flags+=(--arch arm64 --arch x86_64)
fi
swift build "${flags[@]}"
bin="$(swift build "${flags[@]}" --show-bin-path)/MetaEdit"

out="$app/dist/MetaEdit.app"
rm -rf "$out"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
cp "$bin" "$out/Contents/MacOS/MetaEdit"
sed -e "s/__VERSION__/$version/g" "$app/Resources/Info.plist" > "$out/Contents/Info.plist"
printf 'APPL????' > "$out/Contents/PkgInfo"
# Interface strings live in the binary (Sources/MetaEdit/Localization); the .lproj folders tell macOS which
# languages the app speaks, so its own menus (Edit, Window, Services) follow the chosen language.
for lang in en ru es zh-Hans; do
  mkdir -p "$out/Contents/Resources/$lang.lproj"
done
if [[ -f "$app/Resources/AppIcon.icns" ]]; then
  cp "$app/Resources/AppIcon.icns" "$out/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - --identifier io.github.j-tap.MetaEdit "$out"
echo "Built $out (version $version, $archs)"
