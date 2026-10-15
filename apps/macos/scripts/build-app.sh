#!/usr/bin/env bash
# Builds the app bundle into apps/macos/dist. ARCHS=native builds only the host architecture (faster for development).
set -euo pipefail
. "$(dirname "$0")/env.sh"
archs="${ARCHS:-universal}"

"$scripts/build-taglib.sh"

cd "$app"
flags=(-c release)
if [[ "$archs" == "universal" ]]; then
  flags+=(--arch arm64 --arch x86_64)
fi
swift build "${flags[@]}"
bin="$(swift build "${flags[@]}" --show-bin-path)/$executable"

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$bin" "$bundle/Contents/MacOS/$executable"
sed -e "s/__VERSION__/$version/g" -e "s/__MIN_MACOS__/$(min_macos)/g" "$info_plist" > "$bundle/Contents/Info.plist"
printf 'APPL????' > "$bundle/Contents/PkgInfo"
# Interface strings live in the binary (Sources/MetaEdit/Localization); the .lproj folders tell macOS which
# languages the app speaks, so its own menus (Edit, Window, Services) follow the chosen language.
for lang in $(languages); do
  mkdir -p "$bundle/Contents/Resources/$lang.lproj"
done
if [[ -f "$app/Resources/$icon_file" ]]; then
  cp "$app/Resources/$icon_file" "$bundle/Contents/Resources/$icon_file"
fi
codesign --force --sign - --identifier "$bundle_id" "$bundle"
echo "Built $bundle (version $version, $archs)"
