import Foundation

public struct Torrent: Identifiable, Decodable, Equatable, Sendable {
    // Hashes remain stable across daemon restarts; numeric RPC IDs do not.
    public var id: String { hashString }
    public var hashString: String
    public var name: String
    public var status: Int
    public var percentDone: Double
    public var totalSize: Int64
    public var rateDownload: Int64
    public var rateUpload: Int64
    public var peersConnected: Int
    public var uploadRatio: Double
    public var eta: Int
    public var downloadDir: String
    public var errorString: String
    public var isPaused: Bool { status == 0 }
    public var progress: Double { min(1, max(0, percentDone)) }
    public var statusText: String {
        if !errorString.isEmpty { return "Needs attention" }
        return [0: "Paused", 1: "Queued to verify", 2: "Verifying", 3: "Queued", 4: "Downloading", 5: "Queued to seed", 6: "Seeding"][status] ?? "Unknown"
    }
    /// Size-weighted completion across the entire session, including paused and seeded torrents.
    public static func aggregateProgress(_ torrents: [Torrent]) -> Double {
        let total = torrents.reduce(0.0) { $0 + Double(max(0, $1.totalSize)) }
        guard total > 0 else { return 0 }
        let completed = torrents.reduce(0.0) { $0 + Double(max(0, $1.totalSize)) * $1.progress }
        return min(1, max(0, completed / total))
    }
    public static func progressSummary(_ torrents: [Torrent], selectedIDs: Set<String>) -> TorrentProgress {
        let selected = torrents.filter { selectedIDs.contains($0.id) }
        if selected.count == 1, let torrent = selected.first {
            return TorrentProgress(value: torrent.progress, label: "Selected torrent: " + torrent.name)
        }
        if selected.count > 1 {
            return TorrentProgress(value: aggregateProgress(selected), label: "Selected torrents (\(selected.count))")
        }
        return TorrentProgress(value: aggregateProgress(torrents), label: "All torrents")
    }
    public static let fields = ["hashString", "name", "status", "percentDone", "totalSize", "rateDownload", "rateUpload", "peersConnected", "uploadRatio", "eta", "downloadDir", "errorString"]
    public static let modernFields = ["hash_string", "name", "status", "percent_done", "total_size", "rate_download", "rate_upload", "peers_connected", "upload_ratio", "eta", "download_dir", "error_string"]

    public static let examples: [Torrent] = [
        Torrent(hashString: "demo-ubuntu", name: "Ubuntu Desktop 24.04 LTS.iso", status: 4, percentDone: 0.68, totalSize: 6_200_000_000, rateDownload: 12_400_000, rateUpload: 320_000, peersConnected: 42, uploadRatio: 0.24, eta: 160, downloadDir: "~/Downloads", errorString: ""),
        Torrent(hashString: "demo-blender", name: "Big Buck Bunny · Blender Open Movie", status: 6, percentDone: 1, totalSize: 980_000_000, rateDownload: 0, rateUpload: 1_200_000, peersConnected: 18, uploadRatio: 2.48, eta: -1, downloadDir: "~/Downloads", errorString: ""),
        Torrent(hashString: "demo-debian", name: "Debian 12 · arm64 DVD", status: 0, percentDone: 0.32, totalSize: 3_700_000_000, rateDownload: 0, rateUpload: 0, peersConnected: 0, uploadRatio: 0.08, eta: -1, downloadDir: "~/Downloads", errorString: ""),
        Torrent(hashString: "demo-sintel", name: "Sintel · Open Movie · 1080p", status: 4, percentDone: 0.91, totalSize: 1_400_000_000, rateDownload: 4_600_000, rateUpload: 180_000, peersConnected: 12, uploadRatio: 0.67, eta: 28, downloadDir: "~/Downloads", errorString: ""),
        Torrent(hashString: "demo-fedora", name: "Fedora Workstation · Live", status: 3, percentDone: 0, totalSize: 2_300_000_000, rateDownload: 0, rateUpload: 0, peersConnected: 0, uploadRatio: 0, eta: -1, downloadDir: "~/Downloads", errorString: "")
    ]
}

public enum TorrentFilter: String, CaseIterable, Sendable {
    case all = "All", downloading = "Downloading", seeding = "Seeding", paused = "Paused"
    public func includes(_ torrent: Torrent) -> Bool {
        switch self {
        case .all: return true
        case .downloading: return [3, 4].contains(torrent.status)
        case .seeding: return [5, 6].contains(torrent.status)
        case .paused: return torrent.isPaused
        }
    }
}

public enum Display {
    public static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
    public static func speed(_ value: Int64) -> String { bytes(value) + "/s" }
    public static func eta(_ seconds: Int) -> String {
        guard seconds >= 0 else { return "—" }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }
}

public struct TorrentProgress: Sendable {
    public let value: Double
    public let label: String
}
