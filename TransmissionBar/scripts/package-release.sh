#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Build/tests complete before collecting sources for the actual bundled binaries.
bash scripts/build-app.sh
APP="$PWD/dist/TransmissionBar.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(uname -m)
RELEASE="$PWD/dist/release"
mkdir -p "$RELEASE"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/transmissionbar-release.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
python3 scripts/collect-release-sources.py "$APP" "$STAGE/ThirdPartySources"
python3 scripts/release-metadata.py "$APP" "$RELEASE/build-info.json"
# Resource and minimum-system changes require a new app signature.
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto "$APP" "$STAGE/TransmissionBar.app"
ln -s /Applications "$STAGE/Applications"
DMG="$RELEASE/TransmissionBar-$VERSION-macOS-$ARCH.dmg"
# Keep the source archives outside the disk image to keep installation compact.
# Use an installation-only staging directory with an Applications shortcut.
mkdir "$STAGE/Install"
mv "$STAGE/TransmissionBar.app" "$STAGE/Applications" "$STAGE/Install/"
hdiutil create -volname TransmissionBar -srcfolder "$STAGE/Install" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
python3 - "$PWD" "$STAGE" "$RELEASE/TransmissionBar-$VERSION-sources.tar.gz" <<'PY'
from pathlib import Path
import sys, tarfile
project, stage, output = map(Path, sys.argv[1:])
with tarfile.open(output, 'w:gz') as archive:
    archive.add(stage / 'ThirdPartySources', arcname='ThirdPartySources')
    for path in sorted(project.rglob('*')):
        relative = path.relative_to(project)
        if path.is_file() and not any(p in {'.git', '.build', '.swiftpm', '__pycache__', 'dist'} for p in relative.parts):
            archive.add(path, arcname=str(Path('TransmissionBar') / relative), recursive=False)
PY
python3 - "$RELEASE" <<'PYNOTES'
from pathlib import Path
import json, sys
release = Path(sys.argv[1])
info = json.loads((release / 'build-info.json').read_text())
notes = Path('RELEASE-NOTES.md').read_text()
notes += f"\n## Build details\n\nMinimum macOS: {info['minimum_macos']}. Architecture: {info['architecture']}. Engine: {info['engine']}.\n"
(release / 'RELEASE-NOTES.md').write_text(notes)
PYNOTES
(cd "$RELEASE" && shasum -a 256 "TransmissionBar-$VERSION-macOS-$ARCH.dmg" "TransmissionBar-$VERSION-sources.tar.gz" > SHA256SUMS.txt)
printf '\nRelease files ready in %s\n' "$RELEASE"
