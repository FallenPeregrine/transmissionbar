#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Build TorrentBar on a Mac with Xcode Command Line Tools installed." >&2
  exit 1
fi
if pgrep -x TorrentBar >/dev/null 2>&1 || pgrep -x TransmissionBar >/dev/null 2>&1; then
  echo "Quit the running TransmissionBar or TorrentBar using its Quit button before building this update." >&2
  exit 1
fi
if [[ "${1:-}" == "--skip-tests" ]]; then
  echo "Skipping tests by request."
else
  if ! xcrun --find xctest >/dev/null 2>&1; then
    echo "Tests require full Xcode. Select it with xcode-select, or use: bash scripts/build-app.sh --skip-tests" >&2
    exit 1
  fi
  swift test
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "Building the bundled engine requires Homebrew and transmission-cli on this Mac." >&2
  exit 1
fi
ENGINE="$(brew --prefix transmission-cli)/bin/transmission-daemon"
if [[ ! -x "$ENGINE" ]]; then
  echo "Run brew install transmission-cli, then build again." >&2
  exit 1
fi
swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"
OUTPUT_APP="$PWD/dist/TransmissionBar.app"
mkdir -p "$PWD/dist"
STAGING_ROOT="$(mktemp -d "$PWD/dist/.transmissionbar-build.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP="$STAGING_ROOT/TransmissionBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/TransmissionBar.icns "$APP/Contents/Resources/TransmissionBar.icns"
cp "$BINARY_DIR/TorrentBar" "$APP/Contents/MacOS/TransmissionBar"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TransmissionBar</string>
<key>CFBundleIdentifier</key><string>local.torrentbar.prototype</string>
<key>CFBundleName</key><string>TransmissionBar</string>
<key>CFBundleDisplayName</key><string>TransmissionBar</string>
<key>CFBundleIconFile</key><string>TransmissionBar.icns</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>BitTorrent file</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>org.bittorrent.torrent</string></array>
<key>CFBundleTypeExtensions</key><array><string>torrent</string></array>
</dict></array>
<key>UTImportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>org.bittorrent.torrent</string>
<key>UTTypeDescription</key><string>BitTorrent file</string>
<key>UTTypeConformsTo</key><array><string>public.data</string></array>
<key>UTTypeTagSpecification</key><dict>
<key>public.filename-extension</key><array><string>torrent</string></array>
<key>public.mime-type</key><string>application/x-bittorrent</string>
</dict></dict></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.7</string>
<key>CFBundleVersion</key><string>19</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Connect to your Transmission server.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
python3 scripts/bundle-engine.py "$ENGINE" "$APP"
python3 scripts/bundle-engine.py "$(dirname "$ENGINE")/transmission-create" "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
# Exercise the relocated helpers, rather than only inspecting their signatures.
"$APP/Contents/Helpers/transmission-daemon" --version
"$APP/Contents/Helpers/transmission-create" --help >/dev/null
# Publish only the fully verified app, without stale libraries from old builds.
rm -rf "$OUTPUT_APP"
mv "$APP" "$OUTPUT_APP"
APP="$OUTPUT_APP"
printf '\nBuilt %s\nRun: open "%s"\n' "$APP" "$APP"
