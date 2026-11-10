import AppKit
import SwiftUI
import Combine
import Carbon
import UniformTypeIdentifiers
import TorrentCore
import Quartz

@main
enum TorrentBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    init(width: CGFloat, height: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true; level = .statusBar; backgroundColor = .clear
        isOpaque = false; hasShadow = true; hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TorrentStore()
    private let engine = LocalEngine()
    private var shuttingDown = false
    private var engineStartup: Task<Void, Never>?
    private var reportWindows: [NSWindow] = []
    private var quickLookURL: URL?
    private var creatorProcess: Process?
    private var statusItem: NSStatusItem!
    private var listPanel: FloatingPanel!
    private var detailPanel: FloatingPanel!
    private var preferencesWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotKeyArmed = false
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var screenObserver: NSObjectProtocol?
    private struct FileOpenRequest {
        let urls: [URL]
        var magnet: String? = nil
        let replyToAppKit: Bool
    }
    private var pendingFileOpens: [FileOpenRequest] = []
    private var fileImportTask: Task<Void, Never>?
    private var confirmingAdd = false
    private var engineReady = false
    private var startupError: String?
    private var isOpen = false
    private var isTrackingMenu = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditingMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Keep a fixed-width status item even when its artwork is hidden.
        // The publisher also delivers the saved preference on launch.
        store.$showMenuBarIcon.sink { [weak self] visible in
            self?.statusItem.button?.image = visible ? StatusIcon.make() : nil
        }.store(in: &cancellables)
        statusItem.button?.setAccessibilityLabel("TransmissionBar")
        statusItem.button?.toolTip = "TransmissionBar · Control–Option–T"
        statusItem.button?.sendAction(on: .leftMouseDown)
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
        listPanel = FloatingPanel(width: 718, height: 580)
        detailPanel = FloatingPanel(width: 360, height: 580)
        listPanel.contentView = NSHostingView(rootView: TorrentListView(store: store,
            addMagnet: { [weak self] in self?.addMagnet() },
            addFile: { [weak self] in self?.addFile() },
            preferences: { [weak self] in self?.showPreferences() }))
        detailPanel.contentView = NSHostingView(rootView: TorrentDetailView(store: store))
        store.$selectedID.combineLatest(store.$inspectorVisible).dropFirst().sink { [weak self] pair in
            // @Published emits before the new property is stored; use its emitted value.
            self?.updateDetails(show: pair.0 != nil && pair.1)
        }.store(in: &cancellables)
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
        store.commandHandler = { [weak self] name in self?.handleCommand(name) }
        installMonitors()
        registerShortcut()
        store.shortcutChanged = { [weak self] _ in self?.registerShortcut() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        store.isDemo = false; store.torrents = []
        engineStartup = Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.start()
                guard !shuttingDown, !Task.isCancelled else { return }
                store.endpoint = engine.endpoint; store.username = "torrentbar"; store.password = engine.password
                store.connect()
                engineReady = true
                drainFileOpens()
            } catch {
                guard !shuttingDown else { return }
                startupError = error.localizedDescription
                store.error = error.localizedDescription
                failPendingFileOpens()
                show()
            }
        }
        // The menu bar icon is the entry point; don't interrupt the current app on launch.
    }
    private func installEditingMenu() {
        // Text editing shortcuts are dispatched through the responder chain's
        // menu key equivalents, even in an accessory app's modal text fields.
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let application = NSMenu(title: "TransmissionBar")
        application.addItem(withTitle: "Quit TransmissionBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = application; main.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        enqueueFileOpens(filenames.map { URL(fileURLWithPath: $0) }, replyToAppKit: true)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        enqueueFileOpens(urls, replyToAppKit: false)
    }
    private func enqueueFileOpens(_ urls: [URL], magnet: String? = nil, replyToAppKit: Bool) {
        guard !shuttingDown else {
            if replyToAppKit { NSApp.reply(toOpenOrPrint: .cancel) }
            return
        }
        pendingFileOpens.append(FileOpenRequest(urls: urls, magnet: magnet, replyToAppKit: replyToAppKit))
        if startupError != nil { failPendingFileOpens(); show(); return }
        // Finder may deliver this event before applicationDidFinishLaunching.
        // Keep it queued until our own engine has been authenticated and connected.
        drainFileOpens()
    }
    private func failPendingFileOpens() {
        let pending = pendingFileOpens; pendingFileOpens = []
        for request in pending where request.replyToAppKit { NSApp.reply(toOpenOrPrint: .failure) }
    }
    private func drainFileOpens() {
        guard engineReady, !shuttingDown, fileImportTask == nil, !pendingFileOpens.isEmpty else { return }
        fileImportTask = Task { [weak self] in
            guard let self else { return }
            defer { fileImportTask = nil }
            while !pendingFileOpens.isEmpty && !shuttingDown {
                let request = pendingFileOpens.removeFirst()
                do {
                    // A file-open event must not be silently discarded while another
                    // transfer command is running or a confirmation is open.
                    while store.busy || store.pendingRemoval != nil {
                        try await Task.sleep(nanoseconds: 100_000_000)
                    }
                    try Task.checkCancellation()
                    store.preparingImport = true
                    defer { store.preparingImport = false }
                    let files = try TorrentFileImport.validate(request.urls)
                    var options = TorrentAddOptions()
                    if !store.oneClickAdd {
                        let defaults = try await store.torrentAddDefaults()
                        try Task.checkCancellation()
                        hide()
                        confirmingAdd = true
                        NSApp.activate(ignoringOtherApps: true)
                        let chosen = AddTorrentDialog().confirm(
                            names: request.magnet.map { [$0] } ?? files.map(\.lastPathComponent), defaults: defaults)
                        confirmingAdd = false
                        guard let chosen else {
                            if request.replyToAppKit { NSApp.reply(toOpenOrPrint: .cancel) }
                            if !shuttingDown { show() }
                            continue
                        }
                        options = chosen
                    }
                    try Task.checkCancellation()
                    if let magnet = request.magnet {
                        try await store.importMagnet(magnet, options: options)
                    } else {
                        try await store.importTorrentFiles(files, options: options)
                    }
                    if request.replyToAppKit { NSApp.reply(toOpenOrPrint: .success) }
                    show()
                } catch is CancellationError {
                    confirmingAdd = false
                    if request.replyToAppKit { NSApp.reply(toOpenOrPrint: .cancel) }
                } catch {
                    confirmingAdd = false
                    store.error = error.localizedDescription
                    if request.replyToAppKit { NSApp.reply(toOpenOrPrint: .failure) }
                    show()
                }
            }
        }
    }
    @objc private func toggle() {
        guard store.pendingRemoval == nil, !confirmingAdd else { return }
        isOpen ? hide() : show()
    }
    private func show() {
        guard !confirmingAdd, !shuttingDown else { return }
        guard statusItem.button?.window != nil else { return }
        isOpen = true
        positionPanels()
        listPanel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        updateDetails(show: store.selectedID != nil && store.inspectorVisible)
        store.setVisible(true)
    }
    private func hide() {
        isOpen = false
        listPanel.orderOut(nil); detailPanel.orderOut(nil)
        statusItem.button?.highlight(false)
        store.setVisible(false)
    }
    private func positionPanels() {
        guard let button = statusItem.button, let window = button.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let safe = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let height = min(580, safe.height)
        let width = min(718, safe.width)
        let x = min(max(anchor.maxX - width, safe.minX), safe.maxX - width)
        let y = max(safe.minY, min(anchor.minY - 6, safe.maxY) - height)
        listPanel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        let detailHeight = min(580, height)
        // Prefer the requested left side. If needed, shift the pair right to keep both on screen.
        // On very narrow screens, present the inspector over the list instead of clipping it.
        var listFrame = listPanel.frame
        let detailWidth: CGFloat = min(360, safe.width)
        if listFrame.minX - detailWidth - 10 < safe.minX && safe.width >= width + detailWidth + 10 {
            listFrame.origin.x = safe.minX + detailWidth + 10
            if store.inspectorVisible { listPanel.setFrame(listFrame, display: true) }
        }
        let detailX = max(safe.minX, listFrame.minX - detailWidth - 10)
        detailPanel.setFrame(NSRect(x: detailX, y: listFrame.maxY - detailHeight, width: detailWidth, height: detailHeight), display: true)
    }
    private func updateDetails(show: Bool) {
        guard isOpen else { return }
        if show {
            // Defer until selection has been committed before positioning or drawing.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isOpen, self.store.selectedID != nil, self.store.inspectorVisible else { return }
                self.positionPanels()
                self.detailPanel.orderFrontRegardless()
            }
        } else { detailPanel.orderOut(nil); DispatchQueue.main.async { [weak self] in self?.positionPanels() } }
    }
    @objc private func menuBegan() { isTrackingMenu = true }
    @objc private func menuEnded() { isTrackingMenu = false }
    private func statusContains(_ point: NSPoint) -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
    }
    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // AppKit delivers this monitor on the main thread. Handle the event
            // immediately: a queued hide can race the status button's toggle.
            guard let self, self.isOpen, self.store.pendingRemoval == nil,
                  !self.statusContains(NSEvent.mouseLocation) else { return }
            self.hide()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.isOpen, !self.isTrackingMenu, self.store.pendingRemoval == nil else { return event }
            if event.type == .keyDown {
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if event.window === self.listPanel, modifiers == .command,
                   event.charactersIgnoringModifiers?.lowercased() == "a" {
                    if let editor = self.listPanel.firstResponder as? NSTextView {
                        editor.selectAll(nil)
                    } else {
                        self.store.selectAll()
                    }
                    return nil
                }
                switch event.keyCode {
                case 53: self.hide(); return nil
                case 125: self.store.moveSelection(1); return nil
                case 126: self.store.moveSelection(-1); return nil
                default: return event
                }
            }
            let location = NSEvent.mouseLocation
            let inStatus = self.statusContains(location)
            let inList = self.listPanel.frame.contains(location)
            let inDetails = self.detailPanel.isVisible && self.detailPanel.frame.contains(location)
            if !inStatus && !inList && !inDetails { self.hide() }
            return event
        }
    }
    @objc private func shortcutToggle() {
        guard !store.recordingShortcut else { return }
        guard hotKeyArmed else { return }
        hotKeyArmed = false
        toggle()
    }
    @objc private func shortcutPressed() { hotKeyArmed = !store.recordingShortcut }
    private func registerShortcut() {
        hotKeyArmed = false
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if hotKeyHandler == nil {
            // Toggle once on release, avoiding repeated toggles from key repeat.
            var eventTypes = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            ]
            let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                guard let event else { return noErr }
                let name: Notification.Name = GetEventKind(event) == UInt32(kEventHotKeyPressed) ? .torrentBarHotKeyPressed : .torrentBarHotKey
                NotificationCenter.default.post(name: name, object: nil)
                return noErr
            }, 2, &eventTypes, nil, &hotKeyHandler)
            guard installed == noErr else { store.shortcutAvailable = false; return }
            NotificationCenter.default.addObserver(self, selector: #selector(shortcutToggle), name: .torrentBarHotKey, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(shortcutPressed), name: .torrentBarHotKeyPressed, object: nil)
        }
        let shortcut = store.panelShortcut
        let registered = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: 0x54424152, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        store.shortcutAvailable = registered == noErr
        statusItem.button?.toolTip = "TransmissionBar · " + shortcut.label
    }
    private func showPreferences() {
        hide(); NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.orderOut(nil)
        preferencesWindow = nil
        if preferencesWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "TransmissionBar Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView(store: store, done: { [weak self] in
                self?.preferencesWindow?.orderOut(nil); self?.show()
            }))
            if let content = window.contentView { window.setContentSize(content.fittingSize) }
            window.center(); preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }
    private func addMagnet() {
        hide(); NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Add a torrent hash or magnet link"
        alert.informativeText = "Paste a torrent hash or a full magnet link. A plain hash is converted automatically."
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 26))
        input.placeholderString = "Torrent hash or magnet link"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                let magnet = try MagnetLink.normalized(input.stringValue)
                enqueueFileOpens([], magnet: magnet, replyToAppKit: false)
                break
            } catch {
                alert.informativeText = error.localizedDescription
            }
        }
        show()
    }
    private func addFolder() {
        hide(); NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Add torrent files from a folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folder = panel.url else { show(); return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "torrent" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !files.isEmpty else { store.notice = "No .torrent files in this folder."; show(); return }
            enqueueFileOpens(files, replyToAppKit: false)
        } catch { store.error = error.localizedDescription }
        show()
    }
    private func addFile() {
        hide(); NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Add torrent files"; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        if let type = UTType(filenameExtension: "torrent") { panel.allowedContentTypes = [type] }
        if panel.runModal() == .OK { enqueueFileOpens(panel.urls, replyToAppKit: false) }
        show()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if shuttingDown { return .terminateLater }
        if confirmingAdd { NSApp.abortModal(); return .terminateCancel }
        if creatorProcess?.isRunning == true {
            showReport("Torrent creation in progress", "Wait for torrent creation to finish before quitting.")
            return .terminateCancel
        }
        shuttingDown = true
        store.setVisible(false)
        engineStartup?.cancel()
        fileImportTask?.cancel()
        let unopened = pendingFileOpens; pendingFileOpens = []
        for request in unopened where request.replyToAppKit { NSApp.reply(toOpenOrPrint: .cancel) }
        Task {
            await fileImportTask?.value
            await engineStartup?.value
            do { try await engine.stop(); sender.reply(toApplicationShouldTerminate: true) }
            catch {
                shuttingDown = false
                store.error = error.localizedDescription
                show()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.setVisible(false)
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        NotificationCenter.default.removeObserver(self)
    }
}
private extension Notification.Name {
    static let torrentBarHotKeyPressed = Notification.Name("TorrentBarHotKeyPressed")
    static let torrentBarHotKey = Notification.Name("TorrentBarHotKey") }

extension AppDelegate: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { quickLookURL == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { quickLookURL as NSURL? }

    private func handleCommand(_ name: String) {
        if ["remove", "trash", "removeCompleted"].contains(name) {
            show()
            store.requestRemoval(name)
            return
        }
        if name == "addFolder" { addFolder(); return }
        let selected = store.selected
        let selectedTorrents = store.selectedTorrents
        // Capture the selection before a dialog changes keyboard/window focus.
        hide()
        NSApp.activate(ignoringOtherApps: true)
        let dataURL = selected.map { URL(fileURLWithPath: $0.downloadDir).appendingPathComponent($0.name) }
        switch name {
        case "about": showReport("TransmissionBar", "Native menu bar interface powered by a bundled Transmission engine.\nVersion 0.7 prototype.")
        case "log":
            let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TorrentBar/BundledTransmission/engine.log")
            NSWorkspace.shared.open(path)
        case "reveal": if let dataURL { NSWorkspace.shared.activateFileViewerSelecting([dataURL]) }
        case "quicklook":
            quickLookURL = dataURL
            if let panel = QLPreviewPanel.shared() { panel.dataSource = self; panel.reloadData(); panel.makeKeyAndOrderFront(nil) }
        case "move":
            guard selected != nil else { return }
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            panel.prompt = "Move Here"
            if panel.runModal() == .OK, let path = panel.url?.path { store.moveSelected(to: path) }
            show()
        case "rename":
            guard let selected, let name = prompt("Rename torrent data", value: selected.name) else { return }
            store.renameSelected(name); show()
        case "create": createTorrent()
        default:
            Task {
                do {
                    let client = try store.settingsClient()
                    if name == "resumeWaiting" {
                        let hashes = store.torrents.filter { [3, 5].contains($0.status) }.map(\.hashString)
                        if !hashes.isEmpty { try await client.act(.startNow, hashes: hashes) }
                        await store.refresh(); show()
                    } else if name == "speed" {
                        let settings = try JSONSerialization.jsonObject(with: await client.settings()) as? [String: Any] ?? [:]
                        let enabled = (settings["alt_speed_enabled"] as? Bool) ?? false
                        try await client.saveSettings(JSONSerialization.data(withJSONObject: ["alt_speed_enabled": !enabled]))
                        store.notice = enabled ? "Alternative speed limits off" : "Alternative speed limits on"
                        show()
                    } else if ["export", "share", "magnet"].contains(name), let selected {
                        let paths = try await client.torrentPaths(hash: selected.hashString)
                        if name == "magnet" {
                            guard let magnet = paths["magnet"], !magnet.isEmpty else { throw RPCError.message("Magnet link is unavailable.") }
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(magnet, forType: .string)
                            store.notice = "Magnet link copied"; show()
                        } else {
                            guard let path = paths["file"], !path.isEmpty else { throw RPCError.message("Torrent metadata is not available yet.") }
                            let url = URL(fileURLWithPath: path)
                            if name == "share", let button = statusItem.button {
                                NSSharingServicePicker(items: [url]).show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                            } else {
                                let panel = NSSavePanel(); panel.nameFieldStringValue = selected.name + ".torrent"
                                if panel.runModal() == .OK, let destination = panel.url {
                                    try Data(contentsOf: url).write(to: destination, options: .atomic)
                                }
                            }
                        }
                    } else if ["stats", "port", "blocklist"].contains(name) {
                        let method = name == "stats" ? "session_stats" : name == "port" ? "port_test" : "blocklist_update"
                        let data = try await client.utility(method)
                        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                        if name == "port" {
                            let open = result["port_is_open"] as? Bool ?? result["port-is-open"] as? Bool ?? false
                            showReport("Incoming peer port", open ? "The incoming peer port is reachable." : "The incoming peer port is not reachable from the test service. Outgoing connections can still work.")
                        } else if name == "blocklist" {
                            let count = result["blocklist_size"] as? Int ?? result["blocklist-size"] as? Int ?? 0
                            showReport("Blocklist updated", "Loaded \(count) rules.")
                        } else { showReport("Transfer statistics", statistics(result)) }
                    }
                } catch { store.error = error.localizedDescription; showReport("Command failed", error.localizedDescription) }
            }
        }
    }
    private func prompt(_ title: String, value: String = "") -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 26)); field.stringValue = value
        alert.accessoryView = field; alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func showReport(_ title: String, _ content: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autoresizingMask = [.width, .height]
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 340))
        text.string = content; text.isEditable = false; text.font = .systemFont(ofSize: 13)
        text.textContainerInset = NSSize(width: 16, height: 16); text.autoresizingMask = [.width]
        text.isVerticallyResizable = true; text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; window.contentView = scroll
        reportWindows.removeAll { !$0.isVisible }
        reportWindows.append(window); window.center(); window.makeKeyAndOrderFront(nil)
    }
    private func statistics(_ result: [String: Any]) -> String {
        func section(_ keys: [String], title: String) -> String {
            let object = keys.compactMap { result[$0] as? [String: Any] }.first ?? [:]
            func value(_ modern: String, _ old: String) -> Int64 { (object[modern] as? NSNumber ?? object[old] as? NSNumber)?.int64Value ?? 0 }
            return "\(title)\nDownloaded: \(Display.bytes(value("downloaded_bytes", "downloadedBytes")))\nUploaded: \(Display.bytes(value("uploaded_bytes", "uploadedBytes")))\nTorrents added: \(value("files_added", "filesAdded"))\nActive time: \(value("seconds_active", "secondsActive") / 60) minutes\n"
        }
        return section(["current_stats", "current-stats"], title: "This session") + "\n" + section(["cumulative_stats", "cumulative-stats"], title: "All sessions")
    }
    private func createTorrent() {
        guard creatorProcess?.isRunning != true else { showReport("Torrent creation", "A torrent is already being created."); return }
        let source = NSOpenPanel(); source.canChooseFiles = true; source.canChooseDirectories = true; source.prompt = "Choose Source"
        guard source.runModal() == .OK, let input = source.url else { return }
        guard let tracker = prompt("Tracker announce URL (leave blank for a trackerless torrent)") else { return }
        if !tracker.isEmpty, !["http", "https", "udp"].contains(URL(string: tracker)?.scheme ?? "") {
            showReport("Invalid tracker", "Use an HTTP, HTTPS or UDP announce URL."); return
        }
        let destination = NSSavePanel(); destination.nameFieldStringValue = input.lastPathComponent + ".torrent"
        guard destination.runModal() == .OK, let output = destination.url else { return }
        let binary = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/transmission-create")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { showReport("Creator missing", "Rebuild this version to include transmission-create."); return }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let temporaryTorrent = temp.appendingPathComponent("created.torrent")
            let logURL = temp.appendingPathComponent("log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            let process = Process(); process.executableURL = binary
            process.arguments = ["-o", temporaryTorrent.path] + (tracker.isEmpty ? [] : ["-t", tracker]) + [input.path]
            process.standardOutput = log; process.standardError = log
            try process.run(); creatorProcess = process
            store.notice = "Creating torrent for \(input.lastPathComponent)…"; show()
            Task {
                defer { try? log.close(); try? FileManager.default.removeItem(at: temp); creatorProcess = nil }
                while process.isRunning { try? await Task.sleep(nanoseconds: 200_000_000) }
                do {
                    guard process.terminationStatus == 0 else { throw RPCError.message((try? String(contentsOf: logURL, encoding: .utf8)) ?? "Torrent creation failed.") }
                    try Data(contentsOf: temporaryTorrent).write(to: output, options: .atomic)
                    store.notice = "Torrent file created"
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                } catch { showReport("Torrent creation failed", error.localizedDescription) }
            }
        } catch { try? FileManager.default.removeItem(at: temp); showReport("Torrent creation failed", error.localizedDescription) }
    }
}
