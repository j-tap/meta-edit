#!/usr/bin/env bash
# Runs the test suite. The explicit flags make SwiftPM pick Swift Testing reliably with the Command Line Tools.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
"$here/build-taglib.sh"
cd "$here/.."
swift test --enable-swift-testing --disable-xctest "$@"
