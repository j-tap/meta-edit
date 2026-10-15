#!/usr/bin/env bash
# Wraps dist/MeteEdit.app into dist/MeteEdit-<version>-macos.dmg with an Applications shortcut.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$here/.." && pwd)"
root="$(cd "$app/../.." && pwd)"
version="$(tr -d '[:space:]' < "$root/VERSION")"
bundle="$app/dist/MeteEdit.app"
[[ -d "$bundle" ]] || { echo "build the app first: scripts/build-app.sh" >&2; exit 1; }

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$bundle" "$staging/"
ln -s /Applications "$staging/Applications"
dmg="$app/dist/MeteEdit-$version-macos.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "MeteEdit" -srcfolder "$staging" -ov -format UDZO "$dmg"
echo "Created $dmg"
