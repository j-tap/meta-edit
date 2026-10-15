#!/usr/bin/env bash
# Wraps dist/MetaEdit.app into dist/MetaEdit-<version>-macos.dmg with an Applications shortcut.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$here/.." && pwd)"
root="$(cd "$app/../.." && pwd)"
version="$(tr -d '[:space:]' < "$root/VERSION")"
bundle="$app/dist/MetaEdit.app"
[[ -d "$bundle" ]] || { echo "build the app first: scripts/build-app.sh" >&2; exit 1; }

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$bundle" "$staging/"
ln -s /Applications "$staging/Applications"
dmg="$app/dist/MetaEdit-$version-macos.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "MetaEdit" -srcfolder "$staging" -ov -format UDZO "$dmg"
echo "Created $dmg"
