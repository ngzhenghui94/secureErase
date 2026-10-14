#!/bin/sh
# Package an existing build; release mode signs updates, never installs, notarizes, or publishes.
set -eu
cd "$(dirname "$0")"
MODE=${1:---local}
case "$MODE" in
    --local) APP="$PWD/SecureErase.app" ;;
    --release) APP="$PWD/SecureErase.app" ;;
    *) echo "Usage: $0 [--local|--release]" >&2; exit 1 ;;
esac
[ "$#" -le 1 ] || { echo "Usage: $0 [--local|--release]" >&2; exit 1; }
BINARY="$APP/Contents/MacOS/SecureErase"
[ -x "$BINARY" ] || { echo "Missing app executable: $BINARY" >&2; exit 1; }
PLIST="$APP/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
case "$VERSION" in
    ''|*[!0-9.]*|.*|*.|*..*) echo "Expected a numeric dotted app version, got: $VERSION" >&2; exit 1 ;;
esac
/usr/bin/ruby - "$BINARY" "$PLIST" <<'RUBY'
binary, plist = ARGV
{"CFBundleIdentifier" => "local.secureerase", "CFBundleExecutable" => "SecureErase",
 "CFBundleName" => "Secure Erase", "CFBundlePackageType" => "APPL"}.each do |key, expected|
  value = IO.popen(["/usr/libexec/PlistBuddy", "-c", "Print :#{key}", plist], &:read)
  abort "Expected #{key}=#{expected}" unless $?.success? && value.strip == expected
end
arches = IO.popen(["/usr/bin/lipo", "-archs", binary], &:read)
abort "Expected an arm64-only executable" unless $?.success? && arches.strip == "arm64"
commands = IO.popen(["/usr/bin/otool", "-l", binary], &:read)
abort "Cannot read executable deployment target" unless $?.success?
build = commands.split(/Load command \d+/).find { |command| command.match?(/\bcmd LC_BUILD_VERSION\b/) }
unless build && build.match?(/\bplatform (?:1|MACOS)\s*$/) && build.match?(/\bminos 14\.0(?:\.0)?\s*$/)
  abort "Expected macOS 14.0 executable deployment target"
end
minimum = IO.popen(["/usr/libexec/PlistBuddy", "-c", "Print :LSMinimumSystemVersion", plist], &:read)
abort "Expected bundle minimum macOS 14.0" unless $?.success? && minimum.strip.match?(/\A14\.0(?:\.0)?\z/)
RUBY
/usr/bin/codesign --verify --deep --strict "$APP"
if [ "$MODE" = --release ]; then
    /usr/sbin/spctl --assess --type execute --verbose=2 "$APP"
    /usr/bin/xcrun stapler validate "$APP"
fi
OUT="$PWD/build/homebrew/${MODE#--}"
if [ "$MODE" = --release ]; then
    OUT="$PWD/build/releases/$VERSION/package"
    [ ! -e "$OUT" ] || { echo "Refusing to overwrite release package: $OUT" >&2; exit 1; }
fi
mkdir -p "$OUT/Casks"
ARCHIVE="$OUT/SecureErase-$VERSION-arm64.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
/usr/bin/ruby - "$MODE" "$VERSION" "$ARCHIVE" "$OUT/Casks/secureerase.rb" <<'RUBY'
require "digest"
require "uri"
mode, version, archive, cask = ARGV
url_literal = if mode == "--local"
  "file://#{URI::DEFAULT_PARSER.escape(archive, /[^a-zA-Z0-9\/._~-]/)}".dump
else
  '"https://github.com/ngzhenghui94/secureErase/releases/download/v#{version}/SecureErase-#{version}-arm64.zip"'
end
File.write(cask, <<~CASK)
  cask "secureerase" do
    version #{version.dump}
    sha256 #{Digest::SHA256.file(archive).hexdigest.dump}

    url #{url_literal}
    name "Secure Erase"
    desc "Best-effort overwriting and deletion of files and folders"
    homepage "https://github.com/ngzhenghui94/secureErase"

    depends_on arch: :arm64
    depends_on macos: :sonoma

    app "SecureErase.app"
  end
CASK
RUBY
if [ "$MODE" = --release ]; then
    /usr/bin/ruby - "$PLIST" "$VERSION" "$ARCHIVE" "$OUT" "$PWD/.build/artifacts/sparkle/Sparkle/bin/sign_update" <<'RUBY'
require "open3"
require "tempfile"
plist, version, archive, out, signer = ARGV
abort "Missing official Sparkle signing tool" unless File.executable?(signer)
build, status = Open3.capture2("/usr/libexec/PlistBuddy", "-c", "Print :CFBundleVersion", plist)
build = build.strip
abort "Invalid app build version" unless status.success? && build.match?(/\A\d+(?:\.\d+)*\z/)
sign = lambda do |label, *arguments|
  output, _errors, status = Open3.capture3(signer, "--account", "local.swissKnife", *arguments)
  abort "#{label} failed; private command output withheld" unless status.success?
  output.strip
end
signature = sign.call("Archive signing", "-p", archive)
abort "Invalid Sparkle EdDSA signature" unless signature.match?(/\A[A-Za-z0-9+\/]{86}==\z/)
sign.call("Archive signature verification", "--verify", archive, signature)
length = File.size(archive)
abort "Empty update archive" unless length.positive?
url = "https://github.com/ngzhenghui94/secureErase/releases/download/v#{version}/SecureErase-#{version}-arm64.zip"
Tempfile.create(["appcast-", ".xml"], out) do |feed|
  feed.write(<<~XML)
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>SecureErase Updates</title>
        <link>https://github.com/ngzhenghui94/homebrew-tap</link>
        <description>Signed SecureErase updates for Apple Silicon.</description>
        <item>
          <title>SecureErase #{version}</title>
          <sparkle:version>#{build}</sparkle:version>
          <sparkle:shortVersionString>#{version}</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <enclosure url="#{url}" length="#{length}" type="application/octet-stream" sparkle:edSignature="#{signature}" />
        </item>
      </channel>
    </rss>
  XML
  feed.flush
  sign.call("Appcast signing", feed.path)
  sign.call("Appcast signature verification", "--verify", feed.path)
  File.rename(feed.path, File.join(out, "appcast.xml"))
end
puts "PASS: update archive and appcast EdDSA signatures verified."
RUBY
fi
printf 'Archive: %s\nCask: %s\n' "$ARCHIVE" "$OUT/Casks/secureerase.rb"
if [ "$MODE" = --release ]; then
    printf 'Appcast: %s\n' "$OUT/appcast.xml"
fi
