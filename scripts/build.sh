#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"
arch="${ARCH:-$(uname -m)}"
minimum=13.0
version=26.06
case "$arch" in
  arm64)
    archive=7z2606-mac.tar.xz
    checksum=b6f17920b4240940461dac8ef4009891881ac44d2a5ead625ede2ec8472185dd
    ;;
  x86_64)
    archive=7z2606-mac-x64.tar.xz
    checksum=3af68b124052da7fc2a246c96b0bea6a68bfee389baa788f4cead1a133445586
    ;;
  *)
    echo "Unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

build="$root/build/$arch"
app="$build/7zip.app"
contents="$app/Contents"
extension="$contents/PlugIns/FinderExtension.appex"
mkdir -p "$build" "$contents/MacOS" "$contents/Resources" "$extension/Contents/MacOS"

if [[ ! -f "$build/$archive" ]]; then
  scratch="$(mktemp "$build/download.XXXXXXXX")"
  trap 'rm -f "$scratch"' EXIT
  curl --fail --silent --show-error --location --retry 2 \
    "https://github.com/ip7z/7zip/releases/download/$version/$archive" -o "$scratch"
  printf '%s  %s\n' "$checksum" "$scratch" | shasum -a 256 -c
  mv "$scratch" "$build/$archive"
fi
printf '%s  %s\n' "$checksum" "$build/$archive" | shasum -a 256 -c
tar -xf "$build/$archive" -C "$contents/MacOS" 7zz
tar -xf "$build/$archive" -C "$contents/Resources" License.txt
chmod 755 "$contents/MacOS/7zz"
python3 scripts/metadata.py "$contents" "$minimum"

target="$arch-apple-macos$minimum"
xcrun swiftc -O -target "$target" -parse-as-library \
  Sources/App.swift Sources/Actions.swift Sources/ArchiveEngine.swift -o "$contents/MacOS/FinderArchiver"
xcrun swiftc -O -target "$target" -parse-as-library -application-extension \
  -Xlinker -e -Xlinker _NSExtensionMain \
  Sources/FinderExtension.swift Sources/Actions.swift -o "$extension/Contents/MacOS/FinderExtension"

identity="${SIGN_IDENTITY:--}"
if [[ "$identity" != "-" ]] || ! codesign --verify --strict "$contents/MacOS/7zz" 2>/dev/null; then
  codesign --force --sign "$identity" "$contents/MacOS/7zz"
fi
codesign --force --sign "$identity" --entitlements scripts/finder.entitlements "$extension"
codesign --force --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
