#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build
LOCK="$PWD/build/.build-lock"
mkdir "$LOCK" 2>/dev/null || { echo "Build already running or interrupted; inspect $LOCK before removing." >&2; exit 1; }
trap 'rmdir "$LOCK"' EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
[ "$#" -eq 0 ] || { echo "Usage: $0 (builds and publishes a notarized release)" >&2; exit 1; }
APP=build/staging/SecureErase.app
if [ -e "$APP" ]; then
    [ ! -L "$APP" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = local.secureerase ] || { echo "Refusing unrelated staging app" >&2; exit 1; }
    rm -rf "$APP"
fi
swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp "$BIN_DIR/SecureErase" "$APP/Contents/MacOS/"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Secure Erase</string>
  <key>CFBundleIdentifier</key><string>local.secureerase</string>
  <key>CFBundleExecutable</key><string>SecureErase</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>SUFeedURL</key><string>https://raw.githubusercontent.com/ngzhenghui94/homebrew-tap/main/appcasts/secureerase.xml</string>
  <key>SUPublicEDKey</key><string>ogSJSN3POPY/0djBMOpOVyHZxcLbooaAfJYwnin6RCw=</string>
  <key>SURequireSignedFeed</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SUEnableAutomaticChecks</key><false/>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>SUAllowsAutomaticUpdates</key><false/>
  <key>SUSendProfileInfo</key><false/>
  <key>SUEnableSystemProfiling</key><false/>
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
codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/SecureErase" --selftest
python3 release.py --selftest
python3 release.py
echo "Built and published notarized SecureErase.app"
