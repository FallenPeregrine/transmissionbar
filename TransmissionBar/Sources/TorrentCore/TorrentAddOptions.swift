import Foundation

/// Nil values leave Transmission's configured defaults in charge.
public struct TorrentAddOptions: Sendable {
    public var destination: String?
    public var paused: Bool?
    public var priority: Int?

    public init(destination: String? = nil, paused: Bool? = nil, priority: Int? = nil) {
        self.destination = destination; self.paused = paused; self.priority = priority
    }

    func parameters(modern: Bool) throws -> [String: Any] {
        var values: [String: Any] = [:]
        if let destination {
            guard destination.hasPrefix("/"), !destination.contains("\0") else {
                throw RPCError.message("Choose an absolute download folder path.")
            }
            values[modern ? "download_dir" : "download-dir"] = destination
        }
        if let paused { values["paused"] = paused }
        if let priority {
            guard (-1...1).contains(priority) else { throw RPCError.message("Choose Low, Normal or High priority.") }
            values[modern ? "bandwidth_priority" : "bandwidthPriority"] = priority
        }
        return values
    }
}
