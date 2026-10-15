#!/usr/bin/env bash
# Builds TagLib as universal (arm64 + x86_64) static libraries for macOS.
# Output: apps/macos/vendor/taglib/{include,lib}. Re-run is a no-op when the version matches.
set -euo pipefail

TAGLIB_VERSION="2.3.2"
TAGLIB_SHA256="3ca2d8afaa7f1cf7f6ed10e511ebc368bfacd6dcaa3dbfa690b89e502e8963dc"
MIN_MACOS="14.0"

here="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$here/.." && pwd)"
vendor="$app/vendor/taglib"
work="${TAGLIB_BUILD_DIR:-${TMPDIR:-/tmp}/taglib-build-$TAGLIB_VERSION}"

if [[ -f "$vendor/lib/libtag_c.a" && -f "$vendor/.version" && "$(cat "$vendor/.version")" == "$TAGLIB_VERSION" ]]; then
  echo "TagLib $TAGLIB_VERSION already built in $vendor"
  exit 0
fi

mkdir -p "$work" "$vendor"
cd "$work"
tarball="taglib-$TAGLIB_VERSION.tar.gz"
if [[ ! -f "$tarball" ]]; then
  curl -fsSL -o "$tarball" "https://github.com/taglib/taglib/releases/download/v$TAGLIB_VERSION/$tarball"
fi
echo "$TAGLIB_SHA256  $tarball" | shasum -a 256 -c -
rm -rf "taglib-$TAGLIB_VERSION" build
tar xzf "$tarball"

cmake -S "taglib-$TAGLIB_VERSION" -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_BINDINGS=ON \
  -DWITH_ZLIB=ON \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
  -DCMAKE_INSTALL_PREFIX="$vendor" \
  -DCMAKE_INSTALL_LIBDIR=lib
cmake --build build --parallel "$(sysctl -n hw.ncpu)"
cmake --install build
echo "$TAGLIB_VERSION" > "$vendor/.version"
echo "TagLib $TAGLIB_VERSION installed to $vendor"
