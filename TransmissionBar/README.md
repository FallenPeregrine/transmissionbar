# TransmissionBar 0.7

A native macOS menu bar torrent app, inspired by Maccy's interaction model and powered by a bundled Transmission daemon. Transfers keep running when the panel is closed.

## Install

Download the DMG from this fork's [Releases](https://github.com/FallenPeregrine/transmissionbar/releases), drag TransmissionBar into Applications and launch it. Click the menu bar icon or press **Control–Option–T** to open or close the panel. Use **Quit** in the panel to stop the app and its engine.

The initial public beta targets Apple Silicon. Check the release notes for the macOS version tested with its bundled engine. The app is ad-hoc signed and is not Apple notarized.

## Features

- Scrollable transfer list and a separate torrent inspector.
- Multiple selection, **⌘A** for the current filtered list, and right-click actions.
- Add `.torrent` files, batches, magnet links or plain v1 torrent hashes.
- Confirm destination, start state and priority, or enable one-click defaults.
- Progress for the current selection or all transfers when nothing is selected.
- Transmission engine settings plus a configurable panel shortcut and optional icon artwork.

## Build from source

Use a Mac with full Xcode selected, Homebrew and Python 3:

```sh
brew install transmission-cli
cd TransmissionBar
bash scripts/build-app.sh
open dist/TransmissionBar.app
```

The Swift package targets macOS 13+. Bundled Homebrew components can impose a newer minimum system version. Builds use the architecture of the build Mac; the supplied workflow requires Apple Silicon.

For a local DMG, use `bash scripts/package-dmg.sh`. For a public release with bundled notices, matching source archives and checksums, use:

```sh
bash scripts/package-release.sh
```

Upload all files from `dist/release/` to the same GitHub prerelease. End users do not need Homebrew or Xcode to run the bundled app.

## Report a bug

Use the [TransmissionBar bug-report form](https://github.com/FallenPeregrine/transmissionbar/issues/new?template=transmissionbar-bug.yml). Include the app/macOS versions, what you did, what you expected and the exact error. Build logs and screenshots help reproduce UI issues.

## Source layout and credits

This Swift package is in `TransmissionBar/`. The rest of the fork preserves Transmission's upstream source. The app communicates with its bundled daemon over local RPC; it is independent of Transmission's original macOS window interface. See [third-party components](THIRD-PARTY.md), [COPYING](COPYING) and [development notes](DEVELOPMENT-NOTES.md).
