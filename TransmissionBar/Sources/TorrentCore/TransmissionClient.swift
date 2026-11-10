import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Connection: Sendable {
    public let url: URL
    public let username: String
    public let password: String
    public init(endpoint: String, username: String = "", password: String = "") throws {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host))
        else { throw RPCError.message("Use an HTTP localhost address or an HTTPS server address, without embedded credentials.") }
        guard !username.contains(":") else { throw RPCError.message("The username cannot contain a colon.") }
        self.url = url; self.username = username; self.password = password
    }
}
public enum RPCError: LocalizedError {
    case message(String)
    case unavailable(String)
    public var errorDescription: String? { switch self { case .message(let value), .unavailable(let value): return value } }
}

// Never forward authentication to a redirect destination.
private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor TransmissionClient {
    private enum Wire { case modern, legacy }
    private let connection: Connection
    private let session: URLSession
    private var token = ""
    private var wire: Wire?
    public init(connection: Connection, session: URLSession? = nil, timeout: TimeInterval = 12) {
        self.connection = connection
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 1
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func torrents() async throws -> [Torrent] {
        try await negotiate()
        let fields = wire == .modern ? Torrent.modernFields : Torrent.fields
        let result = try await call("torrent_get", params: ["fields": fields])
        guard let items = result["torrents"] as? [[String: Any]] else { throw RPCError.message("The server returned an invalid torrent list.") }
        let decoder = JSONDecoder()
        if wire == .modern { decoder.keyDecodingStrategy = .convertFromSnakeCase }
        return try decoder.decode([Torrent].self, from: JSONSerialization.data(withJSONObject: items))
    }
    public func inspector(hash: String) async throws -> TorrentInspector {
        guard !hash.isEmpty else { throw RPCError.message("Missing torrent hash.") }
        try await negotiate()
        let fields = wire == .modern ? TorrentInspector.modernFields : TorrentInspector.fields
        let result = try await call("torrent_get", params: ["ids": [hash], "fields": fields])
        guard let items = result["torrents"] as? [[String: Any]], let item = items.first else {
            throw RPCError.message("This torrent is no longer available. Refresh the list.")
        }
        let decoder = JSONDecoder()
        if wire == .modern { decoder.keyDecodingStrategy = .convertFromSnakeCase }
        return try decoder.decode(TorrentInspector.self, from: JSONSerialization.data(withJSONObject: item))
    }

    public func setPaused(_ paused: Bool, hash: String) async throws {
        guard !hash.isEmpty else { throw RPCError.message("Missing torrent hash.") }
        try await negotiate()
        _ = try await call(paused ? "torrent_stop" : "torrent_start", params: ["ids": [hash]])
    }
    @discardableResult
    public func add(magnet: String, options: TorrentAddOptions = .init()) async throws -> TorrentAddResult {
        let magnet = try MagnetLink.normalized(magnet)
        try await negotiate()
        var params = try options.parameters(modern: wire == .modern)
        params["filename"] = magnet
        let result = try await call("torrent_add", params: params)
        return try TorrentAddResult.decode(result, modern: wire == .modern)
    }
    public func add(metainfo: Data, options: TorrentAddOptions = .init()) async throws {
        guard !metainfo.isEmpty, metainfo.count <= 20 * 1024 * 1024 else { throw RPCError.message("Choose a .torrent file smaller than 20 MB.") }
        try await negotiate()
        var params = try options.parameters(modern: wire == .modern)
        params["metainfo"] = metainfo.base64EncodedString()
        _ = try await call("torrent_add", params: params)
    }

    public func sessionIdentity() async throws -> String {
        try await negotiate()
        let key = wire == .modern ? "config_dir" : "config-dir"
        let result = try await call("session_get", params: ["fields": [key]])
        guard let directory = result[key] as? String, !directory.isEmpty else {
            throw RPCError.message("The engine did not identify its session directory.")
        }
        return directory
    }
    public func shutdown() async throws {
        try await negotiate()
        _ = try await call("session_close", params: [:])
    }
    public func settings() async throws -> Data {
        try await negotiate()
        let result = try await call("session_get", params: [:])
        var normalized: [String: Any] = [:]
        for field in SessionSetting.all {
            if let value = result[wire == .modern ? field.id : field.legacyKey] { normalized[field.id] = value }
        }
        return try JSONSerialization.data(withJSONObject: normalized)
    }
    public func saveSettings(_ data: Data) async throws {
        try await negotiate()
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RPCError.message("Invalid settings.") }
        var params: [String: Any] = [:]
        for (key, value) in values {
            guard let field = SessionSetting.all.first(where: { $0.id == key }) else { throw RPCError.message("Unknown setting: \(key)") }
            params[wire == .modern ? key : field.legacyKey] = value
        }
        _ = try await call("session_set", params: params)
    }
    public func act(_ action: TransferAction, hashes: [String]) async throws {
        guard !hashes.isEmpty, hashes.allSatisfy({ !$0.isEmpty }) else { throw RPCError.message("Select at least one torrent.") }
        try await negotiate()
        _ = try await call(action.rawValue, params: ["ids": hashes])
    }
    public func remove(hashes: [String], deleteData: Bool) async throws {
        guard !hashes.isEmpty, hashes.allSatisfy({ !$0.isEmpty }) else { throw RPCError.message("Select at least one torrent.") }
        try await negotiate()
        _ = try await call("torrent_remove", params: ["ids": hashes, wire == .modern ? "delete_local_data" : "delete-local-data": deleteData])
    }
    /// Do not report success from a purely local row change: confirm with the engine.
    public func removeAndConfirm(hashes: [String]) async throws -> [Torrent] {
        try await remove(hashes: hashes, deleteData: false)
        let remaining = try await torrents()
        guard Set(remaining.map(\.hashString)).isDisjoint(with: hashes) else {
            throw RPCError.message("Transmission still reports one or more selected transfers. Removal was not confirmed; files were kept.")
        }
        return remaining
    }
    public func move(hash: String, location: String) async throws {
        guard !hash.isEmpty else { throw RPCError.message("Select a torrent.") }
        try await negotiate()
        _ = try await call("torrent_set_location", params: ["ids": [hash], "location": location, "move": true])
    }
    public func rename(hash: String, path: String, name: String) async throws {
        guard !hash.isEmpty, !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { throw RPCError.message("Enter a valid name without slashes.") }
        try await negotiate()
        _ = try await call("torrent_rename_path", params: ["ids": [hash], "path": path, "name": name])
    }
    public func torrentPaths(hash: String) async throws -> [String: String] {
        try await negotiate()
        let fields = wire == .modern ? ["magnet_link", "torrent_file"] : ["magnetLink", "torrentFile"]
        let result = try await call("torrent_get", params: ["ids": [hash], "fields": fields])
        guard let first = (result["torrents"] as? [[String: Any]])?.first else { throw RPCError.message("Torrent no longer exists.") }
        return ["magnet": first[fields[0]] as? String ?? "", "file": first[fields[1]] as? String ?? ""]
    }
    public func utility(_ method: String) async throws -> Data {
        guard ["session_stats", "port_test", "blocklist_update"].contains(method) else { throw RPCError.message("Unknown command.") }
        try await negotiate()
        return try JSONSerialization.data(withJSONObject: await call(method, params: [:]), options: [.prettyPrinted, .sortedKeys])
    }

    private func negotiate() async throws {
        guard wire == nil else { return }
        let response = try await send(["jsonrpc": "2.0", "id": 1, "method": "session_get", "params": ["fields": ["version"]]])
        if response["result"] is [String: Any] { wire = .modern; return }
        // Older Transmission returns a string result for unknown modern methods.
        let oldResult = response["result"] as? String
        let code = (response["error"] as? [String: Any])?["code"] as? Int
        guard oldResult == "method name not recognized" || code == -32601 else {
            throw RPCError.message(Self.errorMessage(response))
        }
        wire = .legacy
        do { _ = try await call("session_get", params: [:]) }
        catch { wire = nil; throw error }
    }
    private func call(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        let body: [String: Any] = wire == .modern
            ? ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
            : ["method": method.replacingOccurrences(of: "_", with: "-"), "arguments": params]
        let response = try await send(body)
        if wire == .modern {
            guard response["error"] == nil, let result = response["result"] as? [String: Any] else { throw RPCError.message(Self.errorMessage(response)) }
            return result
        }
        guard response["result"] as? String == "success" else { throw RPCError.message(Self.errorMessage(response)) }
        return response["arguments"] as? [String: Any] ?? [:]
    }
    private static func errorMessage(_ object: [String: Any]) -> String {
        (object["error"] as? [String: Any])?["message"] as? String ?? object["result"] as? String ?? "Unexpected response from Transmission."
    }
    private func send(_ body: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: body)
        // Bound the CSRF handshake; an incorrect server must not create a retry loop.
        for _ in 0..<3 {
            try Task.checkCancellation()
            var request = URLRequest(url: connection.url)
            request.httpMethod = "POST"; request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "X-Transmission-Session-Id") }
            if !connection.username.isEmpty || !connection.password.isEmpty {
                let credentials = Data("\(connection.username):\(connection.password)".utf8).base64EncodedString()
                request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
            }
            let bytes: Data
            let response: URLResponse
            do { (bytes, response) = try await session.data(for: request) }
            catch let error as URLError {
                switch error.code {
                case .cannotConnectToHost, .cannotFindHost:
                    throw RPCError.unavailable("No RPC server at \(connection.url.host ?? "this host"):\(connection.url.port ?? 443). The local engine is not accepting connections. Check its startup error or engine log if this persists.")
                case .timedOut:
                    throw RPCError.message("Transmission did not respond before the connection timed out. Check that the daemon is running and the port is correct.")
                case .appTransportSecurityRequiresSecureConnection:
                    throw RPCError.message("macOS blocked this connection. Use http://localhost:9092/transmission/rpc for the local daemon, or HTTPS for a remote server.")
                default: throw error
                }
            }
            guard let http = response as? HTTPURLResponse else { throw RPCError.message("Invalid HTTP response.") }
            if http.statusCode == 409, let next = http.value(forHTTPHeaderField: "X-Transmission-Session-Id"), !next.isEmpty { token = next; continue }
            if http.statusCode == 401 { throw RPCError.message("Transmission rejected the username or password.") }
            if http.statusCode == 403 { throw RPCError.message("RPC access denied (403). Check Transmission's RPC IP allowlist.") }
            if http.statusCode == 421 { throw RPCError.message("RPC hostname rejected (421). Try localhost or update Transmission's RPC hostname allowlist.") }
            if http.statusCode == 404 { throw RPCError.message("RPC path not found (404). The address should end in /transmission/rpc.") }
            guard http.statusCode == 200 else { throw RPCError.message("Transmission returned HTTP \(http.statusCode). Check the RPC address and access settings.") }
            guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw RPCError.message("The server did not return a JSON object.") }
            return object
        }
        throw RPCError.message("Transmission repeatedly rejected the session token.")
    }
}
