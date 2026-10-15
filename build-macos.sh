#!/usr/bin/env bash
# Build the Cocoa application, with released or development Lazarus.
#
#   ./build-macos.sh        Debug, into bin/
#   ./build-macos.sh app    Release, then into dist/: Heckers Sketch.app, its
#                           zip, and the bare program the updater fetches
#
# Lazarus is looked for in ~/Developer/lazarus; set LAZARUS_DIR for another.
set -euo pipefail
cd "$(dirname "$0")"
LAZARUS_DIR=${LAZARUS_DIR:-$HOME/Developer/lazarus}
LAZBUILD=${LAZBUILD:-$LAZARUS_DIR/lazbuild}
# The oldest macOS the program will start on.  Only 15 has been run.
MIN_MACOS=11.0
options=(-WM$MIN_MACOS)
# Lazarus 4 has the older SynEdit; the source window knows both
if [ ! -f "$LAZARUS_DIR/components/lazedit/lazedittextattributes.pas" ]; then
  options+=(-dHSK_LEGACY_SYNEDIT)
fi

if [ "${1:-}" != app ]; then
  exec "$LAZBUILD" --ws=cocoa --opt="${options[*]}" "$@" heckerssketch.lpi
fi

app="dist/Heckers Sketch.app"
# first, so a build that fails leaves nothing that looks like its result
rm -rf "$app" dist/icon.iconset dist/heckers-sketch-macos dist/heckers-sketch-macos.zip
"$LAZBUILD" --ws=cocoa --build-mode=Release --opt="${options[*]}" heckerssketch.lpi
# the debug information is in bin/heckers-sketch.dSYM; the symbol table is
# another 4 MB nobody downloading it needs
strip -S -x bin/heckers-sketch
version=$(sed -n "s/.*APP_VERSION = '\(.*\)';.*/\1/p" version.inc)
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist/icon.iconset
cp bin/heckers-sketch "$app/Contents/MacOS/"
cp bin/heckers-sketch dist/heckers-sketch-macos
for size in 16 32 128 256 512; do
  sips -z $size $size icons/app-512.png --out dist/icon.iconset/icon_${size}x${size}.png >/dev/null
done
iconutil -c icns dist/icon.iconset -o "$app/Contents/Resources/heckers-sketch.icns"
rm -rf dist/icon.iconset
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Heckers Sketch</string>
  <key>CFBundleExecutable</key>
  <string>heckers-sketch</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.tonystone31.heckers-sketch</string>
  <key>CFBundleIconFile</key>
  <string>heckers-sketch</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleShortVersionString</key>
  <string>${version#v}</string>
  <key>CFBundleVersion</key>
  <string>${version#v}</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF
# ditto, not zip: it keeps what Finder expects of an application
ditto -c -k --keepParent "$app" dist/heckers-sketch-macos.zip
ls -la dist/heckers-sketch-macos dist/heckers-sketch-macos.zip
