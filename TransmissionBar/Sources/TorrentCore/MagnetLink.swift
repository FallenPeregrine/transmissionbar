import Foundation

public enum MagnetLink {
    /// Accept bare v1 hashes as well as complete magnet URIs. Keep tracker/query
    /// data intact when a complete link is supplied.
    public static func normalized(_ text: String) throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let hexadecimal = Set("0123456789abcdef".utf8)
        let base32 = Set("abcdefghijklmnopqrstuvwxyz234567".utf8)
        if lower.utf8.count == 40, lower.utf8.allSatisfy({ hexadecimal.contains($0) }) {
            return "magnet:?xt=urn:btih:" + lower
        }
        if lower.utf8.count == 32, lower.utf8.allSatisfy({ base32.contains($0) }) {
            return "magnet:?xt=urn:btih:" + lower.uppercased()
        }
        guard let components = URLComponents(string: text), components.scheme?.lowercased() == "magnet",
              components.queryItems?.contains(where: {
                  guard $0.name.lowercased() == "xt", let topic = $0.value?.lowercased() else { return false }
                  return (topic.hasPrefix("urn:btih:") && topic.count > "urn:btih:".count)
                      || (topic.hasPrefix("urn:btmh:") && topic.count > "urn:btmh:".count)
              }) == true,
              let normalized = components.string else {
            throw RPCError.message("Paste a torrent hash (40 hexadecimal characters or 32 Base32 characters), or a complete magnet link. Web page addresses are not supported here.")
        }
        return normalized
    }
}

public struct TorrentAddResult: Sendable {
    public let name: String
    public let hash: String
    public let duplicate: Bool

    static func decode(_ result: [String: Any], modern: Bool) throws -> TorrentAddResult {
        let duplicate = result[modern ? "torrent_duplicate" : "torrent-duplicate"] as? [String: Any]
        guard let torrent = duplicate ?? (result[modern ? "torrent_added" : "torrent-added"] as? [String: Any]),
              let hash = torrent[modern ? "hash_string" : "hashString"] as? String, !hash.isEmpty else {
            throw RPCError.message("Transmission replied without identifying the added torrent. Refresh the list before trying again.")
        }
        return TorrentAddResult(name: torrent["name"] as? String ?? hash, hash: hash, duplicate: duplicate != nil)
    }
}
