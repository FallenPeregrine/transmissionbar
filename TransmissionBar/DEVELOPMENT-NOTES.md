# TransmissionBar 0.7 — self-contained menu bar app

This version launches a bundled Transmission daemon automatically. There is no demo-first startup or connection configuration. Open the app, then click its menu bar icon. The main panel remains 718 points wide and the inspector remains 360 points wide.

## New in 0.7 — paste a plain torrent hash

File → Open Torrent Address accepts a plain v1 torrent hash (40 hexadecimal or 32 Base32 characters) and automatically wraps it in a magnet URI. Leading/trailing clipboard whitespace is ignored; malformed bare hashes are rejected. Complete magnet links retain their existing tracker and other query parameters. Confirmation and one-click defaults behave as before.

Two normalization cases were added, and the one-click RPC test now starts with a bare hash and checks that Transmission receives the complete magnet URI (40 total core cases). Run the usual Mac build for native tests; Swift/AppKit is unavailable in this environment.

## New in 0.6.5 — magnet address input and daemon feedback

The accessory app now installs standard Edit menu commands so Command-V/Command-C/Command-X/Command-A can reach modal text fields. Previously the magnet address dialog had no main Edit menu to dispatch these shortcuts. File → Open Torrent Address trims clipboard whitespace and validates a magnet URI before queuing confirmation; invalid input stays in the address dialog with an explanation. Tracker query data is retained. Valid magnets still use the destination/start/priority confirmation or the existing one-click defaults setting.

Magnet submission now decodes Transmission's added/duplicate result and shows Added magnet or Already in Transmission using the returned name. A missing identity or an RPC error is reported rather than silently treated as success. Successful background polls no longer erase operation errors before they can be read. The same startup-failure handling is used by file and magnet requests.

Six core tests cover modern magnet submission with options and tracker query preservation, legacy duplicate responses, one-click defaults, v2/clipboard normalization, daemon errors and unidentified responses (38 total cases). Tests are included for the Mac build; no Swift/AppKit compiler or running daemon is available here, so these cases have not been executed in this environment. Native paste, modal confirmation and real metadata retrieval require macOS verification.

Mac checks: paste a complete known-working magnet via ⌘V, confirm its destination, and check for Added magnet plus a list entry; repeat it and check Already in Transmission; repeat with one-click add enabled. Starting paused intentionally prevents transfer activity until resumed. If the daemon rejects it, copy the exact error from the panel.

## New in 0.6.4 — Command-A torrent selection

Press ⌘A with the torrent list focused to select all torrents shown by the current search/filter. View → Select All Torrents offers the same action. The selection feeds the existing batch transfer actions and progress banner without automatically opening the inspector. Clicking a row returns keyboard focus to the list; when editing the search text, ⌘A selects that text instead. Clear Selection returns to no selection.

Verify on macOS with several torrents, with a search/filter active, with an empty list, and while editing the search field. Shell/archive checks can run here; native shortcut dispatch requires macOS.

## New in 0.6.3 — batch add confirmation and stable empty state

File → Add torrent files now supports multiple selection. Finder Open With / double-click opens and the Add Folder command use the same serial import queue, including during engine startup. A confirmation dialog lists the incoming torrents and lets you choose their shared download folder, whether to start immediately, and Low/Normal/High priority. Add All applies these choices to the batch; Cancel submits nothing. Use separate batches for different destinations. These choices do not change the global defaults. Magnet links use the same options after pasting the link.

Settings → Application → One-click add using default settings skips confirmation for all these entry points. It is off by default. With it enabled, no destination/start overrides are sent: Transmission uses its configured download folder and start-on-add setting with normal priority.

Polling now uses a separate internal refresh flag: after the first successful snapshot, the empty view no longer alternates between Connecting and No torrents to show every two seconds. The toolbar reserves space for its initial-load spinner and the vector logo image is cached instead of recreated on every view update.

macOS checks to run: add one/many .torrent files from the file picker and Finder (including with the app closed); cancel a batch and verify nothing was added; choose a destination, paused state and priority and inspect the resulting transfers; enable one-click add and verify engine defaults; restart to check preference persistence. Leave an empty panel open through several polling cycles and check the tray/header icons. Four RPC/options tests were added (32 total core cases); this Linux environment cannot run Swift/AppKit or mount the DMG.

## New in 0.6.2 — outlined menu icon and optional artwork

The menu icon uses a thin rounded border, transparent interior and a simplified arrow-and-handle mark from the supplied logo. It follows macOS menu-bar tinting automatically. The panel header uses the same mark; the Finder application icon is unchanged.

Settings → Application → Show menu bar icon takes effect immediately and persists across launches. Turning it off leaves the same square clickable space in the menu bar; clicking it and the configured keyboard shortcut still toggle the panel. It defaults to visible for existing and new installations.

Verify on macOS in light and dark appearances: toggle the preference, click the empty space to open/close the panel, then quit/relaunch to check persistence. Native compilation and visual behaviour cannot be checked in this Linux environment.

## New in 0.6.1 — Finder file opening and selection progress

The bundle now declares .torrent document support and its imported file type. AppKit file/URL open handlers queue incoming files until engine startup succeeds, validate file type/size and serially add their metadata to the engine. This handles cold launch, an already-running app and multiple files. Failed opens are reported in the panel; AppKit file-open requests receive completion/failure replies. Closing the app cancels queued requests before engine shutdown. No default-app association is changed automatically.

After rebuilding and installing the new app into Applications, use Finder Get Info → Open with → TransmissionBar → Change All if macOS still selects an older build. Verify by double-clicking a .torrent with the app closed, again while it is running, and with several files selected.

The banner shows the selected torrent's percentage; multiple selections use their combined size-weighted progress; an empty selection shows all torrents. View → Clear Selection returns to the session view without removing torrents.

There are 28 core tests, including import validation/deduplication and selection-aware progress. Native AppKit delivery, cold-start queueing and Finder default-app behaviour remain to be tested on macOS. This environment has no Swift/AppKit compiler.

## New in 0.6.0 — packaging and restart reliability

Run **bash scripts/package-dmg.sh** from this source folder. It builds/tests, bundles the engine and its libraries plus Finder icon, checks the app signature and helper executables, creates/validates dist/TransmissionBar.dmg, and reveals it in Finder. Build-DMG.command is a double-click Terminal entry point to the same script. Homebrew/Xcode are build-machine requirements only.

The app is assembled in a clean staging folder, then replaces the previous dist app only after its checks pass. This prevents stale dependencies from older builds leaking into the new bundle. hdiutil's deprecation warning is nonfatal; creation and verification must still succeed.

Startup saves a private local credential with owner-only file permissions. It can recover an engine left alive by a previous 0.6+ launch only after authenticating and matching its canonical session-directory path. A different server or an old engine whose credential cannot be verified is left untouched and produces an actionable error; it is never killed or adopted by guessing a PID. Only a verified engine connection is passed to the UI. Quit waits for startup cleanup and engine shutdown, retaining the session lock until that completes; a shutdown timeout keeps the app open with an error.

The earlier version regenerated its password on each app launch. During the first upgrade, quit all older copies and check port 9093 if the new startup message reports a leftover listener. Never delete the torrent session to resolve an authentication error. Configuration, torrent metadata and downloads are preserved.

Install by opening the completed DMG, dragging TransmissionBar into Applications, ejecting the image and launching only the Applications copy. The new version is visible as 0.6.0. It is still a local ad-hoc signed prototype, not a notarized public release.

Verification here: shell syntax, Python bundler syntax, archive/resource/plist checks. There are 26 native XCTest cases including session identity and shutdown compatibility. No Swift/AppKit compiler or macOS image tools are available in this environment, so native compilation, engine recovery, graceful shutdown and DMG mounting are not claimed as tested.

## Build on your Mac

Quit any older TorrentBar before building. From this folder:

```sh
brew install transmission-cli
bash scripts/build-app.sh
open dist/TransmissionBar.app
```

Homebrew is a build-time dependency only. The build copies transmission-daemon and recursively bundles its non-system Mach-O libraries, rewrites dependency paths, and ad-hoc signs the libraries and app. The resulting app is for the architecture of the build Mac. Copy `dist/TransmissionBar.app` into Applications and open it normally. No setup-daemon command is needed.

The engine starts with TorrentBar. Closing the menu panel leaves transfers running. Quit gracefully terminates the engine and waits for it to save its session. A per-session RPC password, loopback-only listener and exclusive session lock prevent accidental connection to another daemon or simultaneous use by two app copies.

## Session locations

- Downloads: `~/Downloads/Transfers`
- State: `~/Library/Application Support/TorrentBar/BundledTransmission`
- Diagnostic log: `engine.log` in that state folder
- Internal RPC port: 9093; peer port: 51415

This is a new session: neither the old desktop app nor the previous launchd service is automatically migrated. If you installed our earlier background service and no longer need its transfers, stop it with:

```sh
launchctl bootout "gui/$(id -u)/local.torrentbar.transmission"
```

Move `~/Library/LaunchAgents/local.torrentbar.transmission.plist` out of LaunchAgents to keep that old service from restarting at login. Its downloads and state remain intact.

## Validation and limits

The earlier interface compiled on your Mac. This version's bundling, native lifecycle and integration have not run on macOS in the creation environment. Python and shell syntax are checked here; the Mac build runs the 26 core tests and verifies the assembled code signature. After building, test launch, a transfer, Quit/relaunch session recovery, and moving the app into Applications. A successful core test run alone does not verify the bundled engine.

The inspector is currently read-only. Settings and the File/Transfers/View/Tools bottom menus are implemented as described in FEATURE-COVERAGE.md; full desktop-app feature parity is not yet complete. There is no engine-crash automatic restart or launch-at-login setting yet. A startup failure is shown in the app with its log location. The browser preview remains an illustrative interface demonstration, not the executable app.

## Distribution

This source package contains no engine binaries. Local builds incorporate the Homebrew Transmission engine and dependency libraries; the generated engine-bundle-manifest.json records their build paths. Before publishing a binary, include the applicable upstream license notices and corresponding source/source offers (Transmission uses GPL), audit dependency licenses, and use Developer ID signing/notarization. Ad-hoc signing here is intended for your local prototype.

References: https://github.com/transmission/transmission and https://formulae.brew.sh/formula/transmission-cli
