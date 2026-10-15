# Shared paths and settings for the macOS scripts. Sourced by them, not run on its own.
# Every value has one source: VERSION for the version, Package.swift for the minimum macOS version,
# Resources/Info.plist for the app name, bundle identifier, icon and interface languages.

scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$(cd "$scripts/.." && pwd)"
root="$(cd "$app/../.." && pwd)"
dist="$app/dist"
info_plist="$app/Resources/Info.plist"

plist_value() {
  plutil -extract "$1" raw -o - "$info_plist"
}

version="$(tr -d '[:space:]' < "$root/VERSION")"
app_name="$(plist_value CFBundleName)"
executable="$(plist_value CFBundleExecutable)"
bundle_id="$(plist_value CFBundleIdentifier)"
icon_file="$(plist_value CFBundleIconFile).icns"
bundle="$dist/$app_name.app"

# Minimum macOS version, from the platforms of Package.swift.
min_macos() {
  (cd "$app" && swift package dump-package) | plutil -extract platforms.0.version raw -o - -
}

# Interface languages, from CFBundleLocalizations.
languages() {
  plutil -extract CFBundleLocalizations json -o - "$info_plist" | tr -d '[]"' | tr ',' ' '
}
