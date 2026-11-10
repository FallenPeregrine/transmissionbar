import Foundation

public struct TorrentInspector: Decodable, Sendable {
    public var hashString: String
    public var comment: String
    public var creator: String
    public var dateCreated: Int
    public var addedDate: Int
    public var isPrivate: Bool
    public var pieceCount: Int
    public var pieceSize: Int64
    public var downloadedEver: Int64
    public var uploadedEver: Int64
    public var files: [InspectorFile]
    public var fileStats: [InspectorFileStats]
    public var trackerStats: [InspectorTracker]
    public var peers: [InspectorPeer]
    public static let fields = ["hashString", "comment", "creator", "dateCreated", "addedDate", "isPrivate", "pieceCount", "pieceSize", "downloadedEver", "uploadedEver", "files", "fileStats", "trackerStats", "peers"]
    public static let modernFields = ["hash_string", "comment", "creator", "date_created", "added_date", "is_private", "piece_count", "piece_size", "downloaded_ever", "uploaded_ever", "files", "file_stats", "tracker_stats", "peers"]
    public static func example(for torrent: Torrent) -> TorrentInspector {
        TorrentInspector(hashString: torrent.hashString, comment: "Illustrative inspector data for the demo workspace.", creator: "Transmission", dateCreated: 1720000000, addedDate: 1793700000, isPrivate: false, pieceCount: 1480, pieceSize: 4194304, downloadedEver: Int64(Double(torrent.totalSize) * torrent.progress), uploadedEver: 240000000,
            files: [InspectorFile(name: torrent.name, length: torrent.totalSize, bytesCompleted: Int64(Double(torrent.totalSize) * torrent.progress))],
            fileStats: [InspectorFileStats(wanted: true, priority: 0)],
            trackerStats: [InspectorTracker(id: 1, host: "tracker.example.org", announce: "https://tracker.example.org/announce", seederCount: 42, leecherCount: 8, lastAnnounceResult: "Demo tracker — not contacted", lastAnnounceSucceeded: true, nextAnnounceTime: 0)],
            peers: [InspectorPeer(address: "192.0.2.10", port: 51413, clientName: "Transmission (demo)", progress: 1, isEncrypted: true, rateToClient: torrent.rateDownload, rateToPeer: torrent.rateUpload)])
    }
}
public struct InspectorFile: Decodable, Sendable {
    public var name: String
    public var length: Int64
    public var bytesCompleted: Int64
    public var progress: Double { length == 0 ? 1 : min(1, max(0, Double(bytesCompleted) / Double(length))) }
}
public struct InspectorFileStats: Decodable, Sendable {
    public var wanted: Bool
    public var priority: Int
    enum CodingKeys: String, CodingKey { case wanted, priority }
    public init(wanted: Bool, priority: Int) { self.wanted = wanted; self.priority = priority }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy implementations can serialize booleans as 0/1.
        if let value = try? c.decode(Bool.self, forKey: .wanted) { wanted = value }
        else { wanted = try c.decode(Int.self, forKey: .wanted) != 0 }
        priority = try c.decode(Int.self, forKey: .priority)
    }
}
public struct InspectorTracker: Decodable, Identifiable, Sendable {
    public var id: Int
    public var host: String
    public var announce: String
    public var seederCount: Int
    public var leecherCount: Int
    public var lastAnnounceResult: String
    public var lastAnnounceSucceeded: Bool
    public var nextAnnounceTime: Int
}
public struct InspectorPeer: Decodable, Sendable {
    public var address: String
    public var port: Int
    public var clientName: String
    public var progress: Double
    public var isEncrypted: Bool
    public var rateToClient: Int64
    public var rateToPeer: Int64
}
