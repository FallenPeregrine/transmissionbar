import Foundation

public struct SessionSetting: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let section: String
    public let kind: Kind
    public enum Kind: Sendable { case toggle, integer(Int, Int), decimal, text, choice([String]) }
    public var legacyKey: String {
        switch id {
        case "seed_ratio_limit": return "seedRatioLimit"
        case "seed_ratio_limited": return "seedRatioLimited"
        default: return id.replacingOccurrences(of: "_", with: "-")
        }
    }
    public static let all: [SessionSetting] = [
        .init(id: "download_dir", title: "Download folder", section: "Transfers", kind: .text),
        .init(id: "incomplete_dir_enabled", title: "Use a folder for incomplete downloads", section: "Transfers", kind: .toggle),
        .init(id: "incomplete_dir", title: "Incomplete folder", section: "Transfers", kind: .text),
        .init(id: "rename_partial_files", title: "Append .part to incomplete files", section: "Transfers", kind: .toggle),
        .init(id: "start_added_torrents", title: "Start transfers when added", section: "Transfers", kind: .toggle),
        .init(id: "sequential_download", title: "Download sequentially by default", section: "Transfers", kind: .toggle),
        .init(id: "trash_original_torrent_files", title: "Trash source .torrent files (engine-side files only)", section: "Transfers", kind: .toggle),
        .init(id: "download_queue_enabled", title: "Limit active downloads", section: "Queues", kind: .toggle),
        .init(id: "download_queue_size", title: "Active downloads", section: "Queues", kind: .integer(0, 10000)),
        .init(id: "seed_queue_enabled", title: "Limit active seeds", section: "Queues", kind: .toggle),
        .init(id: "seed_queue_size", title: "Active seeds", section: "Queues", kind: .integer(0, 10000)),
        .init(id: "queue_stalled_enabled", title: "Exclude stalled transfers from queue limits", section: "Queues", kind: .toggle),
        .init(id: "queue_stalled_minutes", title: "Stalled after (minutes)", section: "Queues", kind: .integer(1, 100000)),
        .init(id: "seed_ratio_limited", title: "Stop seeding at ratio", section: "Queues", kind: .toggle),
        .init(id: "seed_ratio_limit", title: "Seed ratio", section: "Queues", kind: .decimal),
        .init(id: "idle_seeding_limit_enabled", title: "Stop idle seeding", section: "Queues", kind: .toggle),
        .init(id: "idle_seeding_limit", title: "Idle seeding limit (minutes)", section: "Queues", kind: .integer(1, 100000)),
        .init(id: "speed_limit_down_enabled", title: "Limit download speed", section: "Bandwidth", kind: .toggle),
        .init(id: "speed_limit_down", title: "Download limit (kB/s)", section: "Bandwidth", kind: .integer(0, 100000000)),
        .init(id: "speed_limit_up_enabled", title: "Limit upload speed", section: "Bandwidth", kind: .toggle),
        .init(id: "speed_limit_up", title: "Upload limit (kB/s)", section: "Bandwidth", kind: .integer(0, 100000000)),
        .init(id: "alt_speed_enabled", title: "Use alternative speed limits", section: "Schedule", kind: .toggle),
        .init(id: "alt_speed_down", title: "Alternative download (kB/s)", section: "Schedule", kind: .integer(0, 100000000)),
        .init(id: "alt_speed_up", title: "Alternative upload (kB/s)", section: "Schedule", kind: .integer(0, 100000000)),
        .init(id: "alt_speed_time_enabled", title: "Schedule alternative limits", section: "Schedule", kind: .toggle),
        .init(id: "alt_speed_time_begin", title: "Begin", section: "Schedule", kind: .integer(0, 1439)),
        .init(id: "alt_speed_time_end", title: "End", section: "Schedule", kind: .integer(0, 1439)),
        .init(id: "alt_speed_time_day", title: "Days", section: "Schedule", kind: .integer(0, 127)),
        .init(id: "peer_port", title: "Incoming peer port", section: "Network", kind: .integer(1, 65535)),
        .init(id: "peer_port_random_on_start", title: "Randomize peer port on launch", section: "Network", kind: .toggle),
        .init(id: "port_forwarding_enabled", title: "Automatically map port (UPnP / NAT-PMP)", section: "Network", kind: .toggle),
        .init(id: "peer_limit_global", title: "Global peer limit", section: "Network", kind: .integer(1, 100000)),
        .init(id: "peer_limit_per_torrent", title: "Peer limit per torrent", section: "Network", kind: .integer(1, 100000)),
        .init(id: "dht_enabled", title: "Distributed hash table (DHT)", section: "Network", kind: .toggle),
        .init(id: "pex_enabled", title: "Peer exchange (PEX)", section: "Network", kind: .toggle),
        .init(id: "lpd_enabled", title: "Local peer discovery", section: "Network", kind: .toggle),
        .init(id: "utp_enabled", title: "Micro Transport Protocol (µTP)", section: "Network", kind: .toggle),
        .init(id: "encryption", title: "Peer encryption", section: "Privacy", kind: .choice(["required", "preferred", "allowed"])),
        .init(id: "blocklist_enabled", title: "Block peers on blocklist", section: "Privacy", kind: .toggle),
        .init(id: "blocklist_url", title: "Blocklist URL", section: "Privacy", kind: .text),
        .init(id: "default_trackers", title: "Default trackers (one per line)", section: "Advanced", kind: .text),
        .init(id: "script_torrent_added_enabled", title: "Run script when added", section: "Scripts", kind: .toggle),
        .init(id: "script_torrent_added_filename", title: "Added script path", section: "Scripts", kind: .text),
        .init(id: "script_torrent_done_enabled", title: "Run script when download completes", section: "Scripts", kind: .toggle),
        .init(id: "script_torrent_done_filename", title: "Completed script path", section: "Scripts", kind: .text),
        .init(id: "script_torrent_done_seeding_enabled", title: "Run script when seeding completes", section: "Scripts", kind: .toggle),
        .init(id: "script_torrent_done_seeding_filename", title: "Seeding complete script path", section: "Scripts", kind: .text)
    ]
}
public enum TransferAction: String, Sendable {
    case start = "torrent_start", stop = "torrent_stop", startNow = "torrent_start_now"
    case verify = "torrent_verify", reannounce = "torrent_reannounce"
    case top = "queue_move_top", up = "queue_move_up", down = "queue_move_down", bottom = "queue_move_bottom"
}
