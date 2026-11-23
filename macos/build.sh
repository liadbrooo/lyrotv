#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test "$(uname -s)" = Darwin || { echo "macOS/Xcode erforderlich"; exit 1; }
OUT="$PWD/dist"
APP="$OUT/Lyro Motion.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TMP/AppIcon.iconset"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -parse-as-library -O -target "$arch-apple-macos13.0" -sdk "$SDK" LyroMotion.swift -o "$TMP/LyroMotion-$arch"
done
lipo -create "$TMP/LyroMotion-arm64" "$TMP/LyroMotion-x86_64" -output "$APP/Contents/MacOS/LyroMotion"
cp Info.plist "$APP/Contents/Info.plist"
xcrun swift icon.swift "$TMP/icon.png"
for n in 16 32 128 256 512; do
  sips -z "$n" "$n" "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_$n"x"$n.png" >/dev/null
  d=$((n*2))
  sips -z "$d" "$d" "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_$n"x"$n@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"
lipo "$APP/Contents/MacOS/LyroMotion" -verify_arch arm64 x86_64
lipo -archs "$APP/Contents/MacOS/LyroMotion"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/LyroMotion-1.0.0-universal.zip"
mkdir "$TMP/dmg"
ditto "$APP" "$TMP/dmg/Lyro Motion.app"
ln -s /Applications "$TMP/dmg/Applications"
hdiutil create -volname "Lyro Motion" -srcfolder "$TMP/dmg" -format UDZO -ov "$OUT/LyroMotion-1.0.0-universal.dmg"
cd "$OUT"
shasum -a 256 *.zip *.dmg > SHA256SUMS.txt
