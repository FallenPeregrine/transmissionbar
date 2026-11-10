import SwiftUI
import TorrentCore

struct PanelSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.12)))
    }
}

struct TorrentListView: View {
    @ObservedObject var store: TorrentStore
    let addMagnet: () -> Void
    let addFile: () -> Void
    let preferences: () -> Void
    var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: StatusIcon.make()).resizable().frame(width: 16, height: 16).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("TransmissionBar 0.7").font(.headline)
                    }
                    Spacer()
                    ZStack {
                        if store.isLoading { ProgressView().controlSize(.small) }
                    }.frame(width: 16, height: 16).accessibilityHidden(!store.isLoading)
                    HStack(spacing: 12) {
                        Button(action: addFile) { Image(systemName: "doc.badge.plus") }.help("Add torrent file")
                        Button { store.commandHandler?("addFolder") } label: { Image(systemName: "folder.badge.plus") }.help("Add .torrent files from a folder")
                        Button { store.act(.stop) } label: { Image(systemName: "pause.fill") }.help("Pause selected torrents").disabled(store.selectedIDs.isEmpty || !store.canAct)
                        Button { store.act(.start) } label: { Image(systemName: "play.fill") }.help("Resume selected torrents").disabled(store.selectedIDs.isEmpty || !store.canAct)
                    }.buttonStyle(.plain)
                    Text("\(store.activeCount) active · \(store.torrents.count) total").font(.caption.monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
                }.padding(16)
                HStack(spacing: 14) {
                    Label(Display.speed(store.downloadSpeed), systemImage: "arrow.down").foregroundStyle(.blue)
                    Label(Display.speed(store.uploadSpeed), systemImage: "arrow.up").foregroundStyle(.green)
                    ProgressView(value: store.bannerProgress.value)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(store.bannerProgress.label + " progress")
                        .accessibilityValue("\(Int(store.bannerProgress.value * 100)) percent")
                        .help(store.bannerProgress.label + ": \(Int(store.bannerProgress.value * 100))%")
                    Text(store.isDemo ? "SAMPLE DATA" : store.isConnected ? "LIVE" : "OFFLINE")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }.font(.caption.monospacedDigit()).padding(.horizontal, 16).padding(.bottom, 12)
                Divider()
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a torrent", text: $store.query).textFieldStyle(.plain)
                        .accessibilityLabel("Find a torrent")
                    if !store.query.isEmpty {
                        Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }.padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12).padding(.top, 12)
                Picker("Filter torrents", selection: $store.filter) {
                    ForEach(TorrentFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().padding(12)
                if let error = store.error {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 8)
                }
                if let notice = store.notice {
                    Text(notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(store.filtered) { torrent in
                                TorrentRow(torrent: torrent, selected: store.selectedIDs.contains(torrent.id),
                                           enabled: store.canAct,
                                           select: {
                                               let flags = NSEvent.modifierFlags
                                               // A row click transfers keyboard commands away from the search editor.
                                               NSApp.keyWindow?.makeFirstResponder(nil)
                                               store.select(torrent.id, explicit: true, extend: flags.contains(.shift), toggle: flags.contains(.command), click: true)
                                           },
                                           compact: store.compact,
                                           toggle: { store.toggle(torrent) })
                                    .background(RightClickSelection(select: { store.rightClick(torrent.id) }, menu: { NativeTransferMenu.make(store: store) }))
                                    .id(torrent.id)
                            }
                            if store.filtered.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: store.isLoading ? "network" : "tray").font(.title)
                                    Text(store.isLoading ? "Connecting…" : store.torrents.isEmpty ? "No torrents to show" : "No matching torrents")
                                    Text(store.isDemo ? "Try a different search or filter." : "Check your connection or add a torrent.").font(.caption)
                                }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 50)
                            }
                        }.padding(.horizontal, 8).padding(.bottom, 8)
                    }.onChange(of: store.selectedID) { id in if let id { proxy.scrollTo(id) } }
                }
                Divider()
                BottomMenus(store: store, addMagnet: addMagnet, addFile: addFile, preferences: preferences)
            }
        }
        .disabled(store.pendingRemoval != nil)
        .overlay {
            if let request = store.pendingRemoval { RemovalConfirmation(store: store, request: request) }
        }
        .onChange(of: store.query) { _ in store.reconcileSelection() }
        .onChange(of: store.filter) { _ in store.reconcileSelection() }
    }
}

private struct TorrentRow: View {
    let torrent: Torrent
    let selected: Bool
    let enabled: Bool
    let select: () -> Void
    let compact: Bool
    let toggle: () -> Void
    private var tint: Color { torrent.isPaused ? .secondary : torrent.status == 6 ? .green : .blue }
    var body: some View {
        HStack(spacing: 10) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(torrent.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Int(torrent.progress * 100))%") .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if !compact { ProgressView(value: torrent.progress).tint(tint) }
                    HStack(spacing: 4) {
                        Text(torrent.statusText).foregroundStyle(tint)
                        Text("· \(Display.bytes(torrent.totalSize))").foregroundStyle(.secondary)
                        Spacer()
                        if torrent.rateDownload > 0 { Text(Display.speed(torrent.rateDownload)).foregroundStyle(.secondary) }
                    }.font(.system(size: 11)).monospacedDigit()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(torrent.name)
            Button(action: toggle) { Image(systemName: torrent.isPaused ? "play.fill" : "pause.fill").frame(width: 22, height: 28) }
                .buttonStyle(.plain).disabled(!enabled)
                .accessibilityLabel("\(torrent.isPaused ? "Resume" : "Pause") \(torrent.name)")
        }.padding(12)
            .background(selected ? Color.accentColor.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .accessibilityElement(children: .contain)
    }
}

struct TorrentDetailView: View {
    @ObservedObject var store: TorrentStore
    @State private var tab = "Files"
    private let tabs = ["Files", "Trackers", "Peers", "Info"]
    var body: some View {
        PanelSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Torrent inspector", systemImage: "info.circle").font(.headline)
                    Spacer()
                    if store.inspectorLoading { ProgressView().controlSize(.small) }
                    Button { store.closeInspector() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Close inspector")
                }
                if let torrent = store.selected {
                    Text(torrent.name).font(.system(size: 13, weight: .medium)).lineLimit(2).help(torrent.name)
                    Picker("Inspector section", selection: $tab) {
                        ForEach(tabs, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Divider()
                    if let error = store.inspectorError {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Button("Retry inspector") { store.loadInspector() }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if let detail = store.inspector, detail.hashString == torrent.hashString {
                                switch tab {
                                case "Files": files(detail)
                                case "Trackers": trackers(detail)
                                case "Peers": peers(detail)
                                default: info(detail, torrent: torrent)
                                }
                            } else if store.inspectorLoading {
                                Text("Loading inspector…").foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                    Divider()
                    Text("Torrent inspector")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
    @ViewBuilder private func files(_ detail: TorrentInspector) -> some View {
        if detail.files.isEmpty { Text("Waiting for file metadata.").foregroundStyle(.secondary) }
        ForEach(Array(detail.files.enumerated()), id: \.offset) { index, file in
            VStack(alignment: .leading, spacing: 6) {
                Label(file.name, systemImage: "doc").font(.caption).textSelection(.enabled)
                ProgressView(value: file.progress)
                HStack {
                    Text("\(Display.bytes(file.bytesCompleted)) / \(Display.bytes(file.length))")
                    Spacer()
                    Text("\(Int(file.progress * 100))%")
                }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                if index < detail.fileStats.count {
                    let stat = detail.fileStats[index]
                    Text("\(stat.wanted ? "Included" : "Skipped") · Priority: \(stat.priority > 0 ? "High" : stat.priority < 0 ? "Low" : "Normal")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Divider()
        }
    }
    @ViewBuilder private func trackers(_ detail: TorrentInspector) -> some View {
        if detail.trackerStats.isEmpty { Text("No trackers. This torrent may use DHT or peer exchange.").foregroundStyle(.secondary) }
        ForEach(detail.trackerStats) { tracker in
            VStack(alignment: .leading, spacing: 7) {
                Text(tracker.host).font(.system(size: 12, weight: .semibold))
                Text(tracker.announce).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Seeds: \(count(tracker.seederCount))    Peers: \(count(tracker.leecherCount))").font(.caption)
                Text(tracker.lastAnnounceResult.isEmpty ? "Not announced yet" : tracker.lastAnnounceResult)
                    .font(.caption).foregroundStyle(tracker.lastAnnounceSucceeded ? Color.secondary : Color.orange)
                if tracker.nextAnnounceTime > 0 { Text("Next announce: \(date(tracker.nextAnnounceTime))").font(.caption2).foregroundStyle(.secondary) }
            }
            Divider()
        }
    }
    @ViewBuilder private func peers(_ detail: TorrentInspector) -> some View {
        if detail.peers.isEmpty { Text("No connected peers.").foregroundStyle(.secondary) }
        ForEach(Array(detail.peers.enumerated()), id: \.offset) { _, peer in
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(peer.address).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Image(systemName: peer.isEncrypted ? "lock.fill" : "lock.open")
                        .accessibilityLabel(peer.isEncrypted ? "Encrypted" : "Unencrypted")
                }
                Text(peer.clientName.isEmpty ? "Unknown client" : peer.clientName).font(.caption).foregroundStyle(.secondary)
                Text("Port \(peer.port) · \(Int(min(1, max(0, peer.progress)) * 100))% available").font(.caption2)
                Text("↓ \(Display.speed(peer.rateToClient))    ↑ \(Display.speed(peer.rateToPeer))").font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
        }
    }
    @ViewBuilder private func info(_ detail: TorrentInspector, torrent: Torrent) -> some View {
        property("Save location", torrent.downloadDir)
        property("Torrent hash", detail.hashString)
        Button("Copy hash") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(detail.hashString, forType: .string) }
            .controlSize(.small)
        property("Privacy", detail.isPrivate ? "Private torrent" : "Public torrent")
        property("Created by", detail.creator.isEmpty ? "Not specified" : detail.creator)
        property("Created", date(detail.dateCreated))
        property("Added", date(detail.addedDate))
        property("Pieces", "\(detail.pieceCount) × \(Display.bytes(detail.pieceSize))")
        property("Downloaded / uploaded", "\(Display.bytes(detail.downloadedEver)) / \(Display.bytes(detail.uploadedEver))")
        if !detail.comment.isEmpty { property("Comment", detail.comment) }
    }
    private func property(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func date(_ timestamp: Int) -> String {
        timestamp > 0 ? Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .shortened) : "—"
    }
    private func count(_ value: Int) -> String { value < 0 ? "—" : String(value) }
}


struct RemovalConfirmation: View {
    @ObservedObject var store: TorrentStore
    let request: TorrentStore.RemovalRequest
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
            VStack(alignment: .leading, spacing: 16) {
                Text(request.trash ? "Remove transfers and trash data?" : "Remove transfers from the list?").font(.headline)
                Text("\(request.torrents.count) selected transfer(s)")
                Text(request.trash ? "Downloaded data will be moved to macOS Trash." : "Downloaded files will be kept.").foregroundStyle(.secondary)
                HStack {
                    if store.removing { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Cancel") { store.pendingRemoval = nil }.disabled(store.removing)
                    Button(request.trash ? "Move to Trash" : "Remove") { store.confirmRemoval() }
                        .buttonStyle(.borderedProminent).disabled(store.removing)
                }
            }.padding(24).frame(width: 430).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).shadow(radius: 16)
        }.clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
