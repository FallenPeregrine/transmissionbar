import AppKit
import Combine
import TorrentCore

@MainActor
final class TorrentStore: ObservableObject {
    @Published var torrents = Torrent.examples
    @Published var selectedID: String? = nil { didSet { if oldValue != selectedID { loadInspector() } } }
    @Published private(set) var selectedIDs = Set<String>()
    private var selection = TorrentSelection()
    private var listRevision = 0
    struct RemovalRequest {
        let torrents: [Torrent]
        let trash: Bool
    }
    @Published var pendingRemoval: RemovalRequest?
    @Published var removing = false
    @Published var preparingImport = false
    @Published var skipRemovalConfirmation = UserDefaults.standard.bool(forKey: "skipRemovalConfirmation") {
        didSet { UserDefaults.standard.set(skipRemovalConfirmation, forKey: "skipRemovalConfirmation") }
    }
    var activeCount: Int { torrents.filter { [2, 4, 6].contains($0.status) }.count }
    func requestRemoval(_ name: String) {
        guard canAct, !removing, pendingRemoval == nil else { return }
        let targets = name == "removeCompleted" ? torrents.filter { $0.progress >= 1 } : selectedTorrents
        guard !targets.isEmpty else { error = "Select a torrent first."; return }
        let request = RemovalRequest(torrents: targets, trash: name == "trash")
        if skipRemovalConfirmation { performRemoval(request) } else { pendingRemoval = request }
    }
    func confirmRemoval() {
        guard let pendingRemoval, !removing else { return }
        performRemoval(pendingRemoval)
    }
    private func performRemoval(_ request: RemovalRequest) {
        removing = true
        Task {
            defer { pendingRemoval = nil; removing = false }
            do { try await removeTransfers(request.torrents, trash: request.trash) }
            catch { self.error = error.localizedDescription }
        }
    }
    @Published var inspectorVisible = false
    private var inspectorPresentation = InspectorPresentation()
    @Published var sortOrder = UserDefaults.standard.string(forKey: "sortOrder") ?? "Name" { didSet { UserDefaults.standard.set(sortOrder, forKey: "sortOrder") } }
    @Published var ascending = (UserDefaults.standard.object(forKey: "ascending") as? Bool) ?? true { didSet { UserDefaults.standard.set(ascending, forKey: "ascending") } }
    @Published var oneClickAdd = UserDefaults.standard.bool(forKey: "oneClickAdd") {
        didSet { UserDefaults.standard.set(oneClickAdd, forKey: "oneClickAdd") }
    }
    private var refreshing = false
    private var hasLoadedSnapshot = false
    private var refreshError: String?
    @Published var showMenuBarIcon = (UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    @Published var compact = UserDefaults.standard.bool(forKey: "compact") { didSet { UserDefaults.standard.set(compact, forKey: "compact") } }
    var commandHandler: ((String) -> Void)?
    @Published var inspector: TorrentInspector?
    @Published var inspectorLoading = false
    @Published var inspectorError: String?
    private var inspectorTask: Task<Void, Never>?
    private var inspectorRevision = UUID()
    @Published var query = ""
    @Published var filter = TorrentFilter.all
    @Published var isDemo = true
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var notice: String?
    @Published var busy = false
    @Published var recordingShortcut = false
    var shortcutChanged: ((PanelShortcut) -> Void)?
    @Published var panelShortcut = PanelShortcut.load() {
        didSet {
            if let data = try? JSONEncoder().encode(panelShortcut) { UserDefaults.standard.set(data, forKey: "panelShortcut") }
            shortcutChanged?(panelShortcut)
        }
    }
    @Published var shortcutAvailable = true
    @Published var endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? "http://localhost:9092/transmission/rpc"
    @Published var username = UserDefaults.standard.string(forKey: "username") ?? ""
    // Session-only secret: never write a password into UserDefaults or a log.
    @Published var password = ""
    private var client: TransmissionClient?
    private var polling: Task<Void, Never>?
    private var generation = UUID()
    private var visible = false
    var selectedTorrents: [Torrent] { filtered.filter { selectedIDs.contains($0.id) } }
    var selected: Torrent? { torrents.first { $0.id == selectedID } }
    var filtered: [Torrent] {
        let values = torrents.filter { filter.includes($0) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
        return values.sorted { left, right in
            let a = ascending ? left : right
            let b = ascending ? right : left
            let comparison: Bool
            switch sortOrder {
            case "Progress": comparison = a.progress == b.progress ? a.name < b.name : a.progress < b.progress
            case "Size": comparison = a.totalSize == b.totalSize ? a.name < b.name : a.totalSize < b.totalSize
            case "State": comparison = a.status == b.status ? a.name < b.name : a.status < b.status
            case "Activity": comparison = a.rateDownload + a.rateUpload == b.rateDownload + b.rateUpload ? a.name < b.name : a.rateDownload + a.rateUpload < b.rateDownload + b.rateUpload
            case "ETA": comparison = (a.eta < 0 ? Int.max : a.eta) == (b.eta < 0 ? Int.max : b.eta) ? a.name < b.name : (a.eta < 0 ? Int.max : a.eta) < (b.eta < 0 ? Int.max : b.eta)
            default: comparison = a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return comparison
        }
    }
    var bannerProgress: TorrentProgress {
        Torrent.progressSummary(torrents, selectedIDs: selectedIDs)
    }
    var downloadSpeed: Int64 { torrents.reduce(0) { $0 + $1.rateDownload } }
    var uploadSpeed: Int64 { torrents.reduce(0) { $0 + $1.rateUpload } }
    var canAct: Bool { !busy && !preparingImport && (isDemo || isConnected) }

    func setVisible(_ value: Bool) {
        visible = value
        polling?.cancel(); polling = nil
        if !value { inspectorTask?.cancel() }
        if value { loadInspector() }
        guard value, !isDemo, client != nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard !Task.isCancelled else { return }
                self?.loadInspector(keepExisting: true)
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }
    @discardableResult
    func connect() -> Bool {
        do {
            let connection = try Connection(endpoint: endpoint, username: username, password: password)
            polling?.cancel(); generation = UUID(); busy = false; isLoading = false; refreshing = false; hasLoadedSnapshot = false
            client = TransmissionClient(connection: connection)
            isDemo = false; isConnected = false; error = nil; notice = nil
            torrents = []; clearSelection()
            UserDefaults.standard.set(endpoint, forKey: "endpoint")
            UserDefaults.standard.set(username, forKey: "username")
            if visible { setVisible(true) } else { Task { await refresh() } }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func useDemo() {
        polling?.cancel(); polling = nil; generation = UUID()
        UserDefaults.standard.set(false, forKey: "autoConnect")
        client = nil; isDemo = true; isConnected = false; isLoading = false; busy = false
        error = nil; notice = nil; torrents = Torrent.examples; clearSelection()
    }
    func refresh() async {
        guard !refreshing, let client, !isDemo else { return }
        let current = generation
        let revision = listRevision
        refreshing = true
        if !hasLoadedSnapshot { isLoading = true }
        defer {
            if generation == current {
                refreshing = false
                if isLoading { isLoading = false }
            }
        }
        do {
            let values = try await client.torrents()
            guard generation == current, revision == listRevision, !Task.isCancelled else { return }
            hasLoadedSnapshot = true
            torrents = values; isConnected = true
            // A successful background poll should clear its own connection
            // error, not erase a rejected add operation before it can be read.
            if error == refreshError { error = nil }
            refreshError = nil
            UserDefaults.standard.set(username.isEmpty && password.isEmpty, forKey: "autoConnect")
            reconcileSelection()
        } catch {
            guard generation == current, revision == listRevision, !Task.isCancelled else { return }
            isConnected = false
            let message = error.localizedDescription
            if self.error == nil || self.error == refreshError { self.error = message }
            refreshError = message
        }
    }
    func useLocalDaemon() {
        endpoint = "http://localhost:9092/transmission/rpc"; username = ""; password = ""
        connect()
    }
    func loadInspector(keepExisting: Bool = false) {
        guard inspectorVisible else { return }
        if keepExisting && inspectorLoading { return }
        inspectorTask?.cancel()
        let revision = UUID(); inspectorRevision = revision
        let current = generation
        if !keepExisting { inspector = nil }
        inspectorError = nil; inspectorLoading = false
        guard let torrent = selected else { return }
        if isDemo { inspector = TorrentInspector.example(for: torrent); return }
        guard let client else { return }
        inspectorLoading = true
        inspectorTask = Task {
            defer { if inspectorRevision == revision { inspectorLoading = false } }
            do {
                let value = try await client.inspector(hash: torrent.hashString)
                guard !Task.isCancelled, generation == current, inspectorRevision == revision else { return }
                inspector = value
            } catch {
                guard !Task.isCancelled, generation == current, inspectorRevision == revision else { return }
                inspectorError = error.localizedDescription
            }
        }
    }
    func select(_ id: String, explicit: Bool, extend: Bool = false, toggle: Bool = false, click: Bool = false) {
        guard explicit else { return }
        if click && !extend && !toggle && selectedIDs == Set([id]) && selectedID == id && inspectorVisible {
            closeInspector()
            return
        }
        selection.select(id, ordered: filtered.map(\.id), extend: extend, toggle: toggle)
        publishSelection(openInspector: true)
    }
    func rightClick(_ id: String) {
        selection.contextSelect(id, ordered: filtered.map(\.id))
        publishSelection(openInspector: false)
    }
    private func publishSelection(openInspector: Bool) {
        selectedIDs = selection.ids
        let same = selectedID == selection.primary
        if openInspector, selection.primary != nil {
            _ = inspectorPresentation.select(explicit: true)
            inspectorVisible = true
        }
        selectedID = selection.primary
        if selectedID == nil { closeInspector() }
        else if same && openInspector { loadInspector() }
    }
    func selectAll() {
        selection.selectAll(ordered: filtered.map(\.id))
        publishSelection(openInspector: false)
    }
    func clearSelection() {
        selection.clear(); publishSelection(openInspector: false)
    }
    func closeInspector() {
        inspectorPresentation.close(); inspectorVisible = false
        inspectorTask?.cancel()
    }
    func showInspector() {
        if let id = selectedID ?? filtered.first?.id {
            selection.select(id, ordered: filtered.map(\.id))
            publishSelection(openInspector: true)
        }
    }
    func settingsClient() throws -> TransmissionClient {
        guard let client, isConnected else { throw RPCError.message("The download engine is not connected.") }
        return client
    }
    func act(_ action: TransferAction, all: Bool = false) {
        let hashes = all ? torrents.map(\.hashString) : selectedTorrents.map(\.hashString)
        guard !hashes.isEmpty else { return }
        run { try await $0.act(action, hashes: hashes) }
    }
    func removeTransfers(_ targets: [Torrent], trash: Bool) async throws {
        guard !targets.isEmpty else { return }
        guard canAct, let client else { throw RPCError.message("Wait for the current operation to finish and try again.") }
        busy = true; error = nil; notice = nil
        listRevision += 1
        let current = generation
        defer { if generation == current { busy = false } }
        var roots: [URL] = []
        if trash {
            // Resolve data locations before removing metadata; startup never re-adds a transfer.
            let data = try await client.settings()
            let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            for torrent in targets {
                var folders = [torrent.downloadDir]
                if let incomplete = settings["incomplete_dir"] as? String, !incomplete.isEmpty { folders.append(incomplete) }
                let candidates = Set(folders.flatMap { folder -> [URL] in
                    let base = URL(fileURLWithPath: folder).standardizedFileURL
                    return [torrent.name, torrent.name + ".part"].compactMap { name in
                        let path = base.appendingPathComponent(name).standardizedFileURL
                        // Never trash outside the torrent's root directory.
                        return path.deletingLastPathComponent() == base ? path : nil
                    }
                }).filter { FileManager.default.fileExists(atPath: $0.path) }
                guard candidates.count <= 1 else { throw RPCError.message("Multiple possible data locations for \(torrent.name). Remove from the list and manage these files in Finder to avoid trashing the wrong copy.") }
                roots.append(contentsOf: candidates)
            }
            try await client.act(.stop, hashes: targets.map(\.hashString))
        }
        let remaining = try await client.removeAndConfirm(hashes: targets.map(\.hashString))
        guard generation == current else { return }
        // Invalidate any list request started before confirmation.
        listRevision += 1
        torrents = remaining; reconcileSelection()
        var failures: [String] = []
        for path in Set(roots) {
            do { try FileManager.default.trashItem(at: path, resultingItemURL: nil) }
            catch { failures.append("\(path.lastPathComponent): \(error.localizedDescription)") }
        }
        notice = "Removed \(targets.count) transfer(s)" + (trash && roots.isEmpty ? "; no local data was found to trash." : ".")
        if !failures.isEmpty { throw RPCError.message("Transfers were removed from Transmission, but some data could not be moved to Trash:\n" + failures.joined(separator: "\n")) }
    }
    func moveSelected(to location: String) {
        guard let t = selected else { return }
        run { try await $0.move(hash: t.hashString, location: location) }
    }
    func renameSelected(_ name: String) {
        guard let t = selected else { return }
        run { try await $0.rename(hash: t.hashString, path: t.name, name: name) }
    }
    func reconcileSelection() {
        selection.retain(Set(filtered.map(\.id)), ordered: filtered.map(\.id))
        publishSelection(openInspector: false)
    }
    func moveSelection(_ delta: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedID } ?? (delta > 0 ? -1 : list.count)
        select(list[min(list.count - 1, max(0, index + delta))].id, explicit: true)
    }
    func toggle(_ torrent: Torrent) {
        guard canAct else { return }
        if isDemo {
            if let index = torrents.firstIndex(where: { $0.id == torrent.id }) {
                torrents[index].status = torrent.isPaused ? (torrent.progress == 1 ? 6 : 4) : 0
                torrents[index].rateDownload = 0; torrents[index].rateUpload = 0
            }
            reconcileSelection(); return
        }
        run { try await $0.setPaused(!torrent.isPaused, hash: torrent.hashString) }
    }
    func torrentAddDefaults() async throws -> [String: Any] {
        // Engine startup is authenticated before the import queue drains. The
        // first torrent-list poll may still be pending, so don't gate on it.
        guard let client, !isDemo else { throw RPCError.message("The download engine is not ready.") }
        return try JSONSerialization.jsonObject(with: await client.settings()) as? [String: Any] ?? [:]
    }
    func importTorrentFiles(_ urls: [URL], options: TorrentAddOptions = .init()) async throws {
        guard let client, !isDemo else { throw RPCError.message("The download engine is not ready to open torrent files.") }
        guard !busy else { throw RPCError.message("A transfer command is still running. Try opening the file again.") }
        let files = try TorrentFileImport.validate(urls)
        guard !files.isEmpty else { return }
        busy = true; listRevision += 1; notice = nil; error = nil
        var imported = 0
        defer { busy = false }
        do {
            for file in files {
                try Task.checkCancellation()
                let accessed = file.startAccessingSecurityScopedResource()
                defer { if accessed { file.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: file)
                try await client.add(metainfo: data, options: options)
                imported += 1
            }
            isConnected = true
            notice = "Opened \(imported) torrent file(s)."
            await refresh()
        } catch is CancellationError { throw CancellationError() }
        catch { await refresh(); throw RPCError.message("Opened \(imported) of \(files.count) torrent files. \(error.localizedDescription)") }
    }
    func importMagnet(_ magnet: String, options: TorrentAddOptions) async throws {
        guard let client, !isDemo, !busy else { throw RPCError.message("The download engine is not ready to add a magnet link.") }
        busy = true; listRevision += 1; error = nil; notice = nil
        defer { busy = false }
        let result = try await client.add(magnet: magnet, options: options)
        await refresh()
        notice = result.duplicate ? "Already in Transmission: \(result.name)." : "Added magnet: \(result.name)."
    }
    private func run(_ operation: @escaping (TransmissionClient) async throws -> Void) {
        guard canAct, let client else { return }
        busy = true; error = nil; notice = nil
        listRevision += 1
        let current = generation
        Task {
            defer { if generation == current { busy = false } }
            do {
                try await operation(client)
                guard generation == current else { return }
                await refresh()
            } catch {
                guard generation == current else { return }
                self.error = error.localizedDescription
            }
        }
    }
}
