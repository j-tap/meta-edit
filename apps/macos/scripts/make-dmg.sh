#!/usr/bin/env bash
# Wraps the app bundle in dist/ into a <name>-<version>-macos.dmg with an Applications shortcut.
set -euo pipefail
. "$(dirname "$0")/env.sh"
[[ -d "$bundle" ]] || { echo "build the app first: scripts/build-app.sh" >&2; exit 1; }

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$bundle" "$staging/"
ln -s /Applications "$staging/Applications"
dmg="$dist/$app_name-$version-macos.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname "$app_name" -srcfolder "$staging" -ov -format UDZO "$dmg"
echo "Created $dmg"
