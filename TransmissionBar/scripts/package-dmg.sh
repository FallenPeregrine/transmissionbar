#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Create the macOS app and DMG on a Mac." >&2
  exit 1
fi
bash scripts/build-app.sh "$@"
APP="$PWD/dist/TransmissionBar.app"
DMG="$PWD/dist/TransmissionBar.dmg"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/transmissionbar-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
# Preserve the completed signature and bundle metadata.
ditto "$APP" "$STAGE/TransmissionBar.app"
ln -s /Applications "$STAGE/Applications"
# hdiutil remains available on the user's Mac; its deprecation warning is
# nonfatal. Keep one well-tested command rather than guessing new diskutil flags.
hdiutil create -volname TransmissionBar -srcfolder "$STAGE" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
printf '\nDMG ready: %s\nOpen it, drag TransmissionBar into Applications, eject the image, then launch the installed app.\n' "$DMG"
open -R "$DMG"
