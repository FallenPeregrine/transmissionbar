# Third-party components

TransmissionBar is an independent menu bar interface using Transmission's local RPC API. Transmission's authors retain ownership of Transmission and its artwork. This project is not an official Transmission release. Maccy inspired the menu bar interaction; no Maccy source is included in this Swift package.

The repository's existing [COPYING](COPYING) terms and [license texts](licenses/) are retained with this addition. Each bundled third-party component retains its own notices and license terms.

A public binary release is built with `bash scripts/package-release.sh`. Alongside the DMG, that command produces a sources archive containing this Swift package, the exact source archives of the Homebrew packages supplying the bundled helpers/libraries, and their installed Homebrew build recipes. Source downloads are checked against Homebrew's SHA-256 metadata. The build stops if installed package versions differ from the source metadata.

The app's `Contents/Resources/Licenses` directory contains notices from those archives. `PROVENANCE.json` records package versions, source URLs, checksums, license identifiers and the bundled binary paths. Publish the matching sources archive and `SHA256SUMS.txt` beside every DMG.

The regular developer `build-app.sh` and `package-dmg.sh` commands produce local test builds. Use `package-release.sh` for the public release bundle with notices and matching source archives.
