# Transmission integration coverage — 0.4.1

This is a native recreation of supported controls, not an embedded copy of Transmission's macOS preferences window. The Transmission macOS XIBs and engine RPC documentation were reviewed for this implementation.

## Settings implemented

47 version-aware engine settings are provided under Transfers, Queues, Bandwidth, Schedule, Network, Privacy, Scripts and Advanced. Only fields returned by the running engine are shown. Apply sends only changed fields. Numeric values and schedule times are validated before sending. The panel also provides compact rows and the application log.

Includes default/incomplete folders, partial filenames, start-on-add, sequential downloads where supported, active queues, stalled queues, ratio and idle-seeding limits, upload/download limits, alternative limits and daily schedule, incoming port, randomization, port mapping, peer limits, DHT/PEX/LPD/µTP, encryption, blocklist URL/update, completion scripts and default trackers.

Changes to download directory and peer port now persist across restarts: the launcher supplies their defaults only when no settings file exists. New torrents honor the engine's start-on-add setting.

## Bottom menus implemented

| Menu | Commands |
| --- | --- |
| File | Create torrent, open torrent file/address, Quick Look, reveal in Finder, move data, rename, export/share .torrent, copy magnet |
| Transfers | Pause/resume selected, resume immediately, pause/resume all, resume queued, remove from list, move data to Trash and remove, remove completed, reannounce, verify, queue movement |
| View | Show/hide inspector, compact rows, name/activity/progress/ETA/size/state sorting, ascending/descending, refresh |
| Tools | Alternative limits, statistics, log, port test, blocklist update, help, about |
| Direct buttons | Settings, Quit |

Remove actions ask for confirmation and target all selected torrents. Removing from the list keeps downloaded files. Trash resolves known complete/incomplete data roots, pauses the torrents, removes them from Transmission, confirms they are absent, then moves found data to macOS Trash. Missing files do not block removal. A Trash failure leaves the transfer removed and reports the remaining file. Ambiguous paths are reported before removing anything, so the user can manage the files explicitly. List requests that predate a mutation cannot overwrite the confirmed result.

Create Torrent packages transmission-create alongside the daemon, supports a source file/folder and an optional tracker, and saves the output only after successful creation. It does not automatically add or seed the resulting torrent.

## Not yet equivalent to the original desktop app

- Groups, colors and automatic group rules.
- Watch-folder import and rules for displaying the add window; pre-add per-file selection/priority.
- Notification sounds, completion notifications, preventing system sleep and automatic removal on seed completion.
- Automatic weekly blocklist update (manual update is implemented).
- Pieces/availability bars; queue/date-added/tracker sorting.
- Default torrent/magnet application registration, automatic app updates, beta update channel.
- Remote web access and Bonjour (the embedded engine control connection is managed by the app).
- A configurable shortcut, launch-at-login and richer create-torrent options (private flag, comment, piece size, multiple trackers).

Window/Dock-specific options such as Dock badges, window minimization and toolbar customization have no direct equivalent in this menu-bar layout. Standard editing commands work in native text fields; a separate bottom-bar Edit menu is not provided.

## Inspector fix

The selected torrents and inspector visibility are independent. Hover is removed entirely. Click to select one torrent, Command-click to toggle additional torrents, or Shift-click to select a range. Right-click inside a selection preserves the group and offers the full Transfers menu. Click or arrow-key selection opens the inspector for the primary torrent; closing it retains selection. Refresh and reopening the main menu do not reopen a dismissed inspector. Native AppKit startup removes the empty SwiftUI Settings scene.

## Verification

22 XCTest cases are included, covering confirmed/unconfirmed removal, repeated list fetches, multi-selection and right-click selection semantics, action IDs, protocol compatibility and settings. They need to be run on macOS. This environment has no Swift/AppKit toolchain, so no native compilation, XCTest run, Finder Trash integration or new menu rendering is claimed here.

References:
- https://github.com/transmission/transmission/blob/main/macosx/Base.lproj/PrefsWindow.xib
- https://github.com/transmission/transmission/blob/main/macosx/Base.lproj/MainMenu.xib
- https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md
- https://github.com/transmission/transmission/blob/main/utils/transmission-create.1
