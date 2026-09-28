#!/bin/sh
set -e
cd "$(dirname "$0")"
APP=SecureErase.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library SecureErase.swift -o "$APP/Contents/MacOS/SecureErase"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Secure Erase</string>
  <key>CFBundleIdentifier</key><string>local.secureerase</string>
  <key>CFBundleExecutable</key><string>SecureErase</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
EOF
# Build the app icon from Resources/AppIcon.png; rerun build.sh to regenerate it.
rm -rf .build/AppIcon.iconset
mkdir -p .build/AppIcon.iconset "$APP/Contents/Resources"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/SecureErase" --selftest
echo "Built $APP"
