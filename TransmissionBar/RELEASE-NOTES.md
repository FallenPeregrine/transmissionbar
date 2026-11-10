# TransmissionBar 0.7 public beta

A macOS menu bar interface powered by the Transmission engine. Open the panel from the menu bar, manage transfers, and close it while downloads finish and then seed.

## Included

- Torrent list with a separate inspector for the selected transfer.
- Torrent-file, magnet-link and plain v1 hash input.
- Batch add confirmation with destination, start state and priority; optional one-click defaults.
- Transfer, queue, bandwidth, schedule, network and application preferences.
- Selection-aware progress banner, configurable toggle shortcut and optional menu icon artwork.

## Install

Download the `.dmg`, open it, drag TransmissionBar into Applications, eject the image and launch the installed app. The app lives in the menu bar and does not open a normal main window. The default panel shortcut is Control–Option–T. Quit from the panel to stop the bundled engine.

This release is for Apple Silicon Macs. The Swift app targets macOS 13+, but its bundled Homebrew components may require a newer macOS; the release's tested OS version must be recorded after installation testing. Intel and universal binaries are not included.

This beta is ad-hoc signed and is not Apple notarized. macOS may require approval in System Settings → Privacy & Security after an attempted launch. No Apple Developer account is needed to build from source.

## Feedback

Please use this repository's TransmissionBar bug-report form. Include macOS version, app version, reproduction steps and the exact visible error. UI and transfer behaviour have been tested locally by the maintainer; the GitHub build result and installation testing for this packaged artifact should be checked before publishing it.

The sources archive includes the Swift app and matching bundled-component source archives and build recipes. `SHA256SUMS.txt` records the download checksums.
