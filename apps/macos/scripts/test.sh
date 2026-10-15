#!/usr/bin/env bash
# Runs the test suite.
# With the Command Line Tools alone, SwiftPM cannot derive the platform paths (xcrun has no PlatformPath
# there), so the Testing framework and its macro plugin are passed explicitly. With Xcode, plain
# `swift test` works and no extra flags are added.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
"$here/build-taglib.sh"
cd "$here/.."

developer="$(xcode-select -p)"
frameworks="$developer/Library/Developer/Frameworks"
plugins="$developer/usr/lib/swift/host/plugins/testing"
extra=()
if [[ -d "$frameworks/Testing.framework" && -d "$plugins" ]]; then
  extra=(
    --build-system native
    -Xswiftc -F -Xswiftc "$frameworks"
    -Xswiftc -plugin-path -Xswiftc "$plugins"
    -Xlinker -rpath -Xlinker "$frameworks"
  )
fi
swift test --enable-swift-testing --disable-xctest "${extra[@]}" "$@"
