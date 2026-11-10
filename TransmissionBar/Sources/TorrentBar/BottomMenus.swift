import SwiftUI
import TorrentCore

struct BottomMenus: View {
    @ObservedObject var store: TorrentStore
    let addMagnet: () -> Void
    let addFile: () -> Void
    let preferences: () -> Void
    private var unavailable: Bool { store.selected == nil || !store.canAct }
    private func command(_ name: String) { store.commandHandler?(name) }
    var body: some View {
        HStack(spacing: 18) {
            Menu("File") {
                Button("Create Torrent File…") { command("create") }
                Button("Open Torrent File…", action: addFile)
                Button("Open Torrent Address…", action: addMagnet)
                Divider()
                Button("Quick Look") { command("quicklook") }.disabled(unavailable)
                Button("Show in Finder") { command("reveal") }.disabled(unavailable)
                Button("Move Data To…") { command("move") }.disabled(unavailable)
                Button("Rename…") { command("rename") }.disabled(unavailable)
                Divider()
                Button("Save Torrent File As…") { command("export") }.disabled(unavailable)
                Button("Share Torrent File…") { command("share") }.disabled(unavailable)
                Button("Copy Magnet Link") { command("magnet") }.disabled(unavailable)
            }.fixedSize()
            Menu("Transfers") {
                TransferCommands(store: store)
            }.fixedSize()
            Menu("View") {
                Button(store.inspectorVisible ? "Hide Inspector" : "Show Inspector") {
                    if store.inspectorVisible { store.closeInspector() } else { store.showInspector() }
                }
                Button("Select All Torrents (⌘A)") { store.selectAll() }.disabled(store.filtered.isEmpty)
                Button("Clear Selection") { store.clearSelection() }.disabled(store.selectedIDs.isEmpty)
                Toggle("Compact View", isOn: $store.compact)
                Menu("Sort Transfers By") {
                    Picker("Sort", selection: $store.sortOrder) {
                        ForEach(["Name", "Activity", "Progress", "ETA", "Size", "State"], id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Ascending", isOn: $store.ascending)
                }
                Button("Refresh") { Task { await store.refresh() } }
            }.fixedSize()
            Menu("Tools") {
                Button("Toggle Alternative Speed Limits") { command("speed") }.disabled(!store.canAct)
                Button("Statistics…") { command("stats") }.disabled(!store.canAct)
                Button("Message Log") { command("log") }
                Button("Test Incoming Port…") { command("port") }.disabled(!store.canAct)
                Button("Update Blocklist…") { command("blocklist") }.disabled(!store.canAct)
                Divider()
                Button("Transmission Help") { NSWorkspace.shared.open(URL(string: "https://transmissionbt.com/help/")!) }
                Button("About TorrentBar") { command("about") }
            }.fixedSize()
            Spacer()
            Button(action: preferences) { Label("Settings", systemImage: "slider.horizontal.3") }.buttonStyle(.plain)
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain)
        }.menuStyle(.borderlessButton).padding(.horizontal, 16).padding(.vertical, 14)
    }
}


/// Shared verbatim by the bottom menu and every row's context menu.
struct TransferCommands: View {
    @ObservedObject var store: TorrentStore
    private var unavailable: Bool { store.selectedIDs.isEmpty || !store.canAct }
    private func command(_ name: String) { store.commandHandler?(name) }
    var body: some View {
        Group {
                Button("Pause Selected") { store.act(.stop) }.disabled(unavailable)
                Button("Resume Selected") { store.act(.start) }.disabled(unavailable)
                Button("Resume Selected Right Away") { store.act(.startNow) }.disabled(unavailable)
                Divider()
                Button("Pause All") { store.act(.stop, all: true) }.disabled(!store.canAct || store.torrents.isEmpty)
                Button("Resume All") { store.act(.start, all: true) }.disabled(!store.canAct || store.torrents.isEmpty)
                Button("Resume All Waiting") { command("resumeWaiting") }.disabled(!store.canAct)
                Divider()
                Button("Remove From List…") { command("remove") }.disabled(unavailable)
                Button("Remove and Trash Data…") { command("trash") }.disabled(unavailable)
                Button("Remove All Completed From List…") { command("removeCompleted") }.disabled(!store.canAct)
                Divider()
                Button("Update Tracker") { store.act(.reannounce) }.disabled(unavailable)
                Button("Verify Local Data") { store.act(.verify) }.disabled(unavailable)
                Menu("Queue Position") {
                    Button("Move to Top") { store.act(.top) }
                    Button("Move Up") { store.act(.up) }
                    Button("Move Down") { store.act(.down) }
                    Button("Move to Bottom") { store.act(.bottom) }
                }.disabled(unavailable)
        }
    }
}
