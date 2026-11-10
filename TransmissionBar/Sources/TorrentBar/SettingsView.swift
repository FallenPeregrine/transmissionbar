import SwiftUI
import TorrentCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var values: [String: String] = [:]
    @Published var dirty = Set<String>()
    @Published var busy = false
    @Published var message: String?
    func set(_ key: String, _ value: String) { values[key] = value; dirty.insert(key) }
    func load(_ store: TorrentStore) async {
        busy = true; defer { busy = false }
        do {
            let client = try store.settingsClient()
            let data = try await client.settings()
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            var next: [String: String] = [:]
            for field in SessionSetting.all {
                guard let value = object[field.id] else { continue }
                if case .toggle = field.kind { next[field.id] = (value as? NSNumber)?.boolValue == true ? "true" : "false" }
                else if field.id == "alt_speed_time_begin" || field.id == "alt_speed_time_end", let minutes = value as? Int {
                    next[field.id] = String(format: "%02d:%02d", minutes / 60, minutes % 60)
                } else { next[field.id] = (value as? String) ?? (value as? NSNumber)?.stringValue ?? "" }
            }
            values = next; dirty = []; message = nil
        } catch { message = error.localizedDescription }
    }
    func save(_ store: TorrentStore) async {
        busy = true; defer { busy = false }
        do {
            var patch: [String: Any] = [:]
            for field in SessionSetting.all where dirty.contains(field.id) {
                let text = values[field.id] ?? ""
                switch field.kind {
                case .toggle: patch[field.id] = text == "true"
                case .integer(let low, let high):
                    let number: Int?
                    if field.id == "alt_speed_time_begin" || field.id == "alt_speed_time_end" {
                        let parts = text.split(separator: ":").compactMap { Int($0) }
                        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { throw RPCError.message("Use HH:mm for \(field.title).") }
                        number = parts[0] * 60 + parts[1]
                    } else { number = Int(text) }
                    guard let number, (low...high).contains(number) else { throw RPCError.message("\(field.title) must be between \(low) and \(high).") }
                    patch[field.id] = number
                case .decimal:
                    guard let number = Double(text), number.isFinite, number >= 0 else { throw RPCError.message("Enter a nonnegative number for \(field.title).") }
                    patch[field.id] = number
                case .choice(let options):
                    guard options.contains(text) else { throw RPCError.message("Choose a value for \(field.title).") }
                    patch[field.id] = text
                case .text: patch[field.id] = text
                }
            }
            let client = try store.settingsClient()
            try await client.saveSettings(JSONSerialization.data(withJSONObject: patch))
            await load(store)
            message = "Settings saved."
        } catch { message = error.localizedDescription }
    }
}

struct PreferencesView: View {
    @ObservedObject var store: TorrentStore
    @StateObject private var model = SettingsModel()
    @State private var section = "Transfers"
    let done: () -> Void
    private let sections = ["Transfers", "Queues", "Bandwidth", "Schedule", "Network", "Privacy", "Scripts", "Advanced", "Application"]
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                List {
                    ForEach(sections, id: \.self) { name in
                        Button { section = name } label: { Text(name).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading) }
                            .buttonStyle(.plain)
                            .listRowBackground(section == name ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                }
                    .listStyle(.sidebar).frame(width: 160)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(section).font(.title2.weight(.semibold))
                        if section == "Application" { applicationSettings }
                        else {
                            ForEach(SessionSetting.all.filter { $0.section == section && model.values[$0.id] != nil }) { field in
                                setting(field)
                            }
                            if section == "Network" {
                                Button("Test incoming port") { store.commandHandler?("port") }
                            }
                            if section == "Privacy" {
                                Button("Update blocklist now") { store.commandHandler?("blocklist") }
                                Text("Save a changed blocklist URL before updating.").font(.caption).foregroundStyle(.secondary)
                            }
                            if section == "Scripts" { Text("Scripts execute on this Mac when the selected event occurs.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            HStack {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.message ?? (model.dirty.isEmpty ? "" : "Unsaved changes")).font(.caption).textSelection(.enabled)
                Spacer()
                Button("Revert") { Task { await model.load(store) } }.disabled(model.busy || model.dirty.isEmpty)
                Button("Apply") { Task { await model.save(store) } }.disabled(model.busy || model.dirty.isEmpty)
                Button("Done", action: done).disabled(!model.dirty.isEmpty).buttonStyle(.borderedProminent)
            }.padding(14)
        }.frame(width: 760, height: 620)
            .task { await model.load(store) }
    }
    private var applicationSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TransmissionBar runs from the menu bar. Closing the panel keeps transfers running; Quit saves the session and stops the engine.")
            HStack {
                Text("Toggle panel")
                Spacer()
                ShortcutRecorder(shortcut: $store.panelShortcut, capturing: $store.recordingShortcut).frame(width: 180, height: 28)
                Button("Reset") { store.panelShortcut = .standard }
            }
            Text("Click the shortcut, then press a key with Command, Control or Option. Press Escape to cancel. Release the shortcut to open or close the panel.").font(.caption).foregroundStyle(.secondary)
            if !store.shortcutAvailable { Text("This shortcut could not be registered. Choose another combination.").foregroundStyle(.orange) }
            Toggle("One-click add using default settings", isOn: $store.oneClickAdd)
            Text("Skip the confirmation panel when adding torrent files or magnet links. Uses Transmission's download folder and start-on-add setting, with normal priority.").font(.caption).foregroundStyle(.secondary)
            Toggle("Show menu bar icon", isOn: $store.showMenuBarIcon)
            Text("When hidden, its empty space in the menu bar still opens and closes the panel. The keyboard shortcut also keeps working.").font(.caption).foregroundStyle(.secondary)
            Toggle("Compact transfer rows", isOn: $store.compact)
            Toggle("Remove transfers and trash data without confirmation", isOn: $store.skipRemovalConfirmation)
            Text("When enabled, removal commands run immediately for the selected torrents. Trashed files can be recovered from macOS Trash.").font(.caption).foregroundStyle(.secondary)
            Button("Open engine log") { store.commandHandler?("log") }
            Text("The engine's local control connection is managed by TorrentBar. Remote web access is not exposed by this build.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { model.values[key] ?? "" }, set: { model.set(key, $0) })
    }
    @ViewBuilder private func setting(_ field: SessionSetting) -> some View {
        switch field.kind {
        case .toggle:
            Toggle(field.title, isOn: Binding(get: { model.values[field.id] == "true" }, set: { model.set(field.id, $0 ? "true" : "false") }))
        case .choice(let options):
            Picker(field.title, selection: binding(field.id)) { ForEach(options, id: \.self) { Text($0.capitalized).tag($0) } }
        case .integer, .decimal:
            if field.id == "alt_speed_time_day" {
                VStack(alignment: .leading) {
                    Text("Schedule days")
                    HStack {
                        ForEach(Array(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].enumerated()), id: \.offset) { index, day in
                            Toggle(day, isOn: Binding(get: { ((Int(model.values[field.id] ?? "0") ?? 0) & (1 << index)) != 0 }, set: { on in
                                let old = Int(model.values[field.id] ?? "0") ?? 0
                                model.set(field.id, String(on ? old | (1 << index) : old & ~(1 << index)))
                            })).toggleStyle(.button)
                        }
                    }
                }
            } else {
                HStack {
                    Text(field.title + (field.id.hasPrefix("alt_speed_time_") ? " (HH:mm)" : ""))
                    Spacer()
                    TextField(field.title, text: binding(field.id)).labelsHidden().textFieldStyle(.roundedBorder).frame(width: 110)
                }
            }
        case .text:
            VStack(alignment: .leading, spacing: 7) {
                Text(field.title)
                if field.id == "default_trackers" {
                    TextEditor(text: binding(field.id)).font(.system(.body, design: .monospaced)).frame(height: 150)
                } else {
                    HStack {
                        TextField(field.title, text: binding(field.id)).labelsHidden().textFieldStyle(.roundedBorder)
                        if field.id.hasSuffix("_dir") || field.id.hasSuffix("_filename") {
                            Button("Choose…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = field.id.hasSuffix("_dir")
                                panel.canChooseFiles = !panel.canChooseDirectories
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let path = panel.url?.path { model.set(field.id, path) }
                            }
                        }
                    }
                }
            }
        }
    }
}
