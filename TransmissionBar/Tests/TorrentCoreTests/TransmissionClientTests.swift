import XCTest
@testable import TorrentCore
import Foundation

private final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class TransmissionClientTests: XCTestCase {
    private func client() throws -> TransmissionClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        return TransmissionClient(connection: try Connection(endpoint: "http://localhost:9091/transmission/rpc"), session: URLSession(configuration: config))
    }
    private static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    private static func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    override func tearDown() { MockProtocol.handler = nil; super.tearDown() }

    func testModernAddSendsBatchOptionsBeforeStartingTransfer() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            if body["method"] as? String == "session_get" {
                return (200, [:], try Self.json(["jsonrpc": "2.0", "id": 1, "result": ["version": "4.1.0"]]))
            }
            XCTAssertEqual(body["method"] as? String, "torrent_add")
            let params = try XCTUnwrap(body["params"] as? [String: Any])
            XCTAssertEqual(params["download_dir"] as? String, "/Volumes/Storage/Downloads")
            XCTAssertEqual(params["paused"] as? Bool, true)
            XCTAssertEqual(params["bandwidth_priority"] as? Int, 1)
            XCTAssertEqual(params["metainfo"] as? String, Data("torrent".utf8).base64EncodedString())
            return (200, [:], try Self.json(["jsonrpc": "2.0", "id": 1, "result": [:]]))
        }
        try await client().add(metainfo: Data("torrent".utf8), options: .init(destination: "/Volumes/Storage/Downloads", paused: true, priority: 1))
    }

    func testLegacyAddMapsDestinationAndPriorityKeys() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            switch body["method"] as? String {
            case "session_get": return (200, [:], try Self.json(["result": "method name not recognized"]))
            case "session-get": return (200, [:], try Self.json(["result": "success", "arguments": [:]]))
            default:
                XCTAssertEqual(body["method"] as? String, "torrent-add")
                let params = try XCTUnwrap(body["arguments"] as? [String: Any])
                XCTAssertEqual(params["download-dir"] as? String, "/tmp/downloads")
                XCTAssertEqual(params["paused"] as? Bool, false)
                XCTAssertEqual(params["bandwidthPriority"] as? Int, -1)
                XCTAssertNil(params["download_dir"])
                return (200, [:], try Self.json(["result": "success", "arguments": [:]]))
            }
        }
        try await client().add(metainfo: Data("torrent".utf8), options: .init(destination: "/tmp/downloads", paused: false, priority: -1))
    }

    func testOneClickAddLeavesSessionDefaultsUnspecified() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            if body["method"] as? String == "session_get" {
                return (200, [:], try Self.json(["jsonrpc": "2.0", "id": 1, "result": ["version": "4.1.0"]]))
            }
            let params = try XCTUnwrap(body["params"] as? [String: Any])
            XCTAssertEqual(Set(params.keys), ["metainfo"])
            return (200, [:], try Self.json(["jsonrpc": "2.0", "id": 1, "result": [:]]))
        }
        try await client().add(metainfo: Data("torrent".utf8))
    }

    func testInvalidAddOptionsAreRejected() throws {
        XCTAssertThrowsError(try TorrentAddOptions(destination: "relative/path").parameters(modern: true))
        XCTAssertThrowsError(try TorrentAddOptions(priority: 2).parameters(modern: false))
    }

    func testModernMagnetAddPreservesTrackerAndConfirmsResult() async throws {
        let hash = String(repeating: "a", count: 40)
        let magnet = "magnet:?xt=urn:btih:" + hash + "&dn=Example&tr=https%3A%2F%2Ftracker.example%2Fannounce%3Fkey%3Dtest"
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            if body["method"] as? String == "session_get" {
                return (200, [:], try Self.json(["result": ["version": "4.1.0"]]))
            }
            XCTAssertEqual(body["method"] as? String, "torrent_add")
            let params = try XCTUnwrap(body["params"] as? [String: Any])
            XCTAssertEqual(params["filename"] as? String, magnet)
            XCTAssertNil(params["metainfo"])
            XCTAssertEqual(params["download_dir"] as? String, "/tmp/downloads")
            XCTAssertEqual(params["paused"] as? Bool, true)
            XCTAssertEqual(params["bandwidth_priority"] as? Int, 1)
            return (200, [:], try Self.json(["result": ["torrent_added": ["id": 1, "name": "Example", "hash_string": hash]]]))
        }
        let result = try await client().add(magnet: "  " + magnet + "\n", options: .init(destination: "/tmp/downloads", paused: true, priority: 1))
        XCTAssertEqual(result.hash, hash); XCTAssertEqual(result.name, "Example"); XCTAssertFalse(result.duplicate)
    }

    func testLegacyMagnetDuplicateIsReported() async throws {
        let hash = String(repeating: "b", count: 40)
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            switch body["method"] as? String {
            case "session_get": return (200, [:], try Self.json(["result": "method name not recognized"]))
            case "session-get": return (200, [:], try Self.json(["result": "success", "arguments": [:]]))
            default:
                XCTAssertEqual(body["method"] as? String, "torrent-add")
                let params = try XCTUnwrap(body["arguments"] as? [String: Any])
                XCTAssertEqual(params["filename"] as? String, "magnet:?xt=urn:btih:" + hash)
                XCTAssertEqual(params["download-dir"] as? String, "/tmp/downloads")
                XCTAssertEqual(params["bandwidthPriority"] as? Int, -1)
                return (200, [:], try Self.json(["result": "success", "arguments": ["torrent-duplicate": ["id": 1, "name": "Existing", "hashString": hash]]]))
            }
        }
        let result = try await client().add(magnet: "magnet:?xt=urn:btih:" + hash, options: .init(destination: "/tmp/downloads", priority: -1))
        XCTAssertTrue(result.duplicate); XCTAssertEqual(result.hash, hash)
    }

    func testOneClickMagnetUsesDefaultsAndHandlesDuplicate() async throws {
        let hash = String(repeating: "c", count: 40)
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            if body["method"] as? String == "session_get" {
                return (200, [:], try Self.json(["result": ["version": "4.1.0"]]))
            }
            let params = try XCTUnwrap(body["params"] as? [String: Any])
            XCTAssertEqual(Set(params.keys), ["filename"])
            XCTAssertEqual(params["filename"] as? String, "magnet:?xt=urn:btih:" + hash)
            return (200, [:], try Self.json(["result": ["torrent_duplicate": ["name": "Existing", "hash_string": hash]]]))
        }
        let result = try await client().add(magnet: hash)
        XCTAssertTrue(result.duplicate)
    }

    func testBareTorrentHashesAreConvertedAutomatically() throws {
        let hex = "0123456789ABCDEF0123456789ABCDEF01234567"
        XCTAssertEqual(try MagnetLink.normalized(" \n" + hex + "\n"), "magnet:?xt=urn:btih:" + hex.lowercased())
        let base32 = "abcdefghijklmnopqrstuvwxyz234567"
        XCTAssertEqual(try MagnetLink.normalized(base32), "magnet:?xt=urn:btih:" + base32.uppercased())
    }

    func testMalformedBareHashesAreRejected() throws {
        for value in [String(repeating: "a", count: 39), String(repeating: "g", count: 40),
                      String(repeating: "0", count: 32), String(repeating: "a", count: 20) + " " + String(repeating: "a", count: 19)] {
            XCTAssertThrowsError(try MagnetLink.normalized(value))
        }
    }

    func testMagnetValidationAcceptsV2AndClipboardWhitespace() throws {
        let v2 = "magnet:?xt=urn:btmh:1220" + String(repeating: "a", count: 64)
        XCTAssertEqual(try MagnetLink.normalized("\n " + v2 + " \n"), v2)
        XCTAssertNoThrow(try MagnetLink.normalized("MAGNET:?xt=URN:BTIH:" + String(repeating: "A", count: 40)))
        XCTAssertThrowsError(try MagnetLink.normalized("magnet:?xt=urn:btih:"))
        XCTAssertThrowsError(try MagnetLink.normalized("magnet:?dn=MissingHash"))
        XCTAssertThrowsError(try MagnetLink.normalized(""))
    }

    func testMagnetDaemonErrorIsNotReportedAsSuccess() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            if body["method"] as? String == "session_get" {
                return (200, [:], try Self.json(["result": ["version": "4.1.0"]]))
            }
            return (200, [:], try Self.json(["error": ["code": 4, "message": "invalid or corrupt torrent file"]]))
        }
        do {
            try await client().add(magnet: "magnet:?xt=urn:btih:" + String(repeating: "d", count: 40))
            XCTFail("Expected daemon error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("invalid or corrupt")) }
    }

    func testUnidentifiedMagnetResponseCannotConfirmSuccess() throws {
        XCTAssertThrowsError(try TorrentAddResult.decode([:], modern: true))
        XCTAssertFalse(try TorrentAddResult.decode(["torrent-added": ["name": "Legacy", "hashString": "hash"]], modern: false).duplicate)
    }

    func testModernNegotiationAndSnakeCaseDecoding() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            XCTAssertEqual(body["jsonrpc"] as? String, "2.0")
            if body["method"] as? String == "session_get" {
                return (200, [:], try Self.json(["result": ["version": "4.1.0"]]))
            }
            XCTAssertEqual(body["method"] as? String, "torrent_get")
            let params = body["params"] as! [String: Any]
            XCTAssertTrue((params["fields"] as! [String]).contains("hash_string"))
            return (200, [:], try Self.json(["result": ["torrents": [[
                "hash_string": "stable-hash", "name": "Example", "status": 4,
                "percent_done": 0.5, "total_size": 1000, "rate_download": 50,
                "rate_upload": 2, "peers_connected": 3, "upload_ratio": 0.1,
                "eta": 10, "download_dir": "/Downloads", "error_string": ""
            ]]]]))
        }
        let values = try await client().torrents()
        XCTAssertEqual(values.first?.id, "stable-hash")
        XCTAssertEqual(values.first?.percentDone, 0.5)
    }
    func testLegacyFallback() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            switch body["method"] as! String {
            case "session_get": return (200, [:], try Self.json(["result": "method name not recognized"]))
            case "session-get": return (200, [:], try Self.json(["result": "success", "arguments": [:]]))
            default:
                XCTAssertEqual(body["method"] as? String, "torrent-get")
                XCTAssertNotNil(body["arguments"])
                return (200, [:], try Self.json(["result": "success", "arguments": ["torrents": []]]))
            }
        }
        let values = try await client().torrents()
        XCTAssertTrue(values.isEmpty)
    }
    func testSessionChallengeRetriesWithHeader() async throws {
        var count = 0
        MockProtocol.handler = { request in
            count += 1
            if count == 1 { return (409, ["X-Transmission-Session-Id": "fresh-token"], Data()) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Transmission-Session-Id"), "fresh-token")
            let body = try Self.body(request)
            let result: [String: Any] = body["method"] as? String == "session_get" ? ["version": "4.1.0"] : ["torrents": []]
            return (200, [:], try Self.json(["result": result]))
        }
        _ = try await client().torrents()
        XCTAssertEqual(count, 3)
    }
    func testChallengeIsBounded() async throws {
        var count = 0
        MockProtocol.handler = { _ in count += 1; return (409, ["X-Transmission-Session-Id": "token"], Data()) }
        do { _ = try await client().torrents(); XCTFail("Expected failure") } catch { XCTAssertTrue(error.localizedDescription.contains("session token")) }
        XCTAssertEqual(count, 3)
    }
    func testAuthenticationFailureDoesNotFallback() async throws {
        var count = 0
        MockProtocol.handler = { _ in count += 1; return (401, [:], Data()) }
        do { _ = try await client().torrents(); XCTFail("Expected failure") } catch { XCTAssertTrue(error.localizedDescription.contains("password")) }
        XCTAssertEqual(count, 1)
    }
    func testPauseTargetsHashAndNeverAllTorrents() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            if body["method"] as? String == "session_get" { return (200, [:], try Self.json(["result": ["version": "4.1.0"]])) }
            XCTAssertEqual(body["method"] as? String, "torrent_stop")
            XCTAssertEqual((body["params"] as? [String: Any])?["ids"] as? [String], ["stable-hash"])
            return (200, [:], try Self.json(["result": [:]]))
        }
        try await client().setPaused(true, hash: "stable-hash")
    }
    func testInvalidMagnetDoesNotSendRequest() async throws {
        MockProtocol.handler = { _ in XCTFail("Must not send"); return (500, [:], Data()) }
        do { try await client().add(magnet: "https://example.com"); XCTFail("Expected failure") } catch { XCTAssertTrue(error.localizedDescription.contains("magnet")) }
    }
    func testConnectionValidation() throws {
        XCTAssertNoThrow(try Connection(endpoint: "http://127.0.0.1:9091/transmission/rpc"))
        XCTAssertNoThrow(try Connection(endpoint: "https://seedbox.example/transmission/rpc"))
        XCTAssertThrowsError(try Connection(endpoint: "http://seedbox.example/transmission/rpc"))
        XCTAssertThrowsError(try Connection(endpoint: "https://user:secret@example.com"))
        XCTAssertThrowsError(try Connection(endpoint: "http://localhost:9091", username: "bad:name"))
    }
    func testQueuedFiltersAndUnknownETA() {
        XCTAssertTrue(TorrentFilter.downloading.includes(Torrent.examples[4]))
        XCTAssertTrue(TorrentFilter.seeding.includes(Torrent.examples[1]))
        XCTAssertTrue(TorrentFilter.paused.includes(Torrent.examples[2]))
        XCTAssertEqual(Display.eta(-2), "—")
        XCTAssertEqual(Display.eta(3601), "1h 0m")
    }
    func testInspectorModernFieldsAndStableHash() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            if body["method"] as? String == "session_get" {
                return (200, [:], try Self.json(["result": ["version": "4.1.0"]]))
            }
            let params = body["params"] as! [String: Any]
            XCTAssertEqual(params["ids"] as? [String], ["hash-123"])
            XCTAssertTrue((params["fields"] as! [String]).contains("tracker_stats"))
            let item: [String: Any] = [
                "hash_string": "hash-123", "comment": "test", "creator": "test",
                "date_created": 0, "added_date": 0, "is_private": false,
                "piece_count": 2, "piece_size": 1024, "downloaded_ever": 512, "uploaded_ever": 0,
                "files": [["name": "folder/file.txt", "length": 2048, "bytes_completed": 512]],
                "file_stats": [["wanted": true, "priority": 1]],
                "tracker_stats": [], "peers": []
            ]
            return (200, [:], try Self.json(["result": ["torrents": [item]]]))
        }
        let detail = try await client().inspector(hash: "hash-123")
        XCTAssertEqual(detail.hashString, "hash-123")
        XCTAssertEqual(detail.files.first?.progress, 0.25)
        XCTAssertEqual(detail.fileStats.first?.priority, 1)
    }
    func testLegacyIntegerFileWanted() throws {
        let data = Data(#"{"wanted":0,"priority":-1}"#.utf8)
        let value = try JSONDecoder().decode(InspectorFileStats.self, from: data)
        XCTAssertFalse(value.wanted)
        XCTAssertEqual(value.priority, -1)
    }
    func testRemovedTorrentInspectorError() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            let result: [String: Any] = body["method"] as? String == "session_get" ? ["version": "4.1.0"] : ["torrents": []]
            return (200, [:], try Self.json(["result": result]))
        }
        do { _ = try await client().inspector(hash: "removed"); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("no longer available")) }
    }
    func testForbiddenHasActionableError() async throws {
        MockProtocol.handler = { _ in (403, [:], Data()) }
        do { _ = try await client().torrents(); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("allowlist")) }
    }

    func testInspectorDismissalSurvivesRepeatedHover() {
        var state = InspectorPresentation()
        XCTAssertTrue(state.select(explicit: false))
        state.close()
        for _ in 0..<10 { XCTAssertFalse(state.select(explicit: false)) }
        XCTAssertFalse(state.isVisible)
        XCTAssertTrue(state.select(explicit: true))
        XCTAssertTrue(state.isVisible)
    }
    func testLegacySettingsKeysAndPartialSave() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            switch body["method"] as? String {
            case "session_get": return (200, [:], try Self.json(["result": "method name not recognized"]))
            case "session-get": return (200, [:], try Self.json(["result": "success", "arguments": ["seedRatioLimit": 2.0, "speed-limit-up": 100]]))
            default:
                XCTAssertEqual(body["method"] as? String, "session-set")
                let args = body["arguments"] as! [String: Any]
                XCTAssertEqual(args.count, 1)
                XCTAssertEqual(args["seedRatioLimit"] as? Double, 3.5)
                return (200, [:], try Self.json(["result": "success", "arguments": [:]]))
            }
        }
        let rpc = try client()
        let data = try await rpc.settings()
        let values = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(values["seed_ratio_limit"] as? Double, 2.0)
        try await rpc.saveSettings(Self.json(["seed_ratio_limit": 3.5]))
    }
    func testEmptyActionCannotAffectAllTorrents() async throws {
        MockProtocol.handler = { _ in XCTFail("No HTTP request expected"); return (500, [:], Data()) }
        do { try await client().act(.stop, hashes: []); XCTFail("Expected failure") } catch {}
        do { try await client().remove(hashes: [], deleteData: true); XCTFail("Expected failure") } catch {}
    }
    func testRemoveKeepsDataByDefaultRequest() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            if body["method"] as? String == "session_get" { return (200, [:], try Self.json(["result": ["version": "4.1.0"]])) }
            XCTAssertEqual(body["method"] as? String, "torrent_remove")
            let params = body["params"] as! [String: Any]
            XCTAssertEqual(params["delete_local_data"] as? Bool, false)
            XCTAssertEqual(params["ids"] as? [String], ["only-this"])
            return (200, [:], try Self.json(["result": [:]]))
        }
        try await client().remove(hashes: ["only-this"], deleteData: false)
    }

    func testConfirmedRemovalIsStillGoneOnNextListFetch() async throws {
        var listRequests = 0
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            switch body["method"] as? String {
            case "session_get": return (200, [:], try Self.json(["result": ["version": "4.1.0"]]))
            case "torrent_remove":
                let params = body["params"] as! [String: Any]
                XCTAssertEqual(params["ids"] as? [String], ["removed"])
                XCTAssertEqual(params["delete_local_data"] as? Bool, false)
                return (200, [:], try Self.json(["result": [:]]))
            default:
                XCTAssertEqual(body["method"] as? String, "torrent_get")
                listRequests += 1
                return (200, [:], try Self.json(["result": ["torrents": []]]))
            }
        }
        let rpc = try client()
        let confirmed = try await rpc.removeAndConfirm(hashes: ["removed"])
        XCTAssertTrue(confirmed.isEmpty)
        let reopened = try await rpc.torrents()
        XCTAssertTrue(reopened.isEmpty)
        XCTAssertEqual(listRequests, 2)
    }
    func testUnconfirmedRemovalReportsFailureInsteadOfHidingRow() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            if body["method"] as? String == "session_get" { return (200, [:], try Self.json(["result": ["version": "4.1.0"]])) }
            if body["method"] as? String == "torrent_remove" { return (200, [:], try Self.json(["result": [:]])) }
            let item: [String: Any] = ["hash_string": "still-here", "name": "test", "status": 0,
                "percent_done": 1.0, "total_size": 100, "rate_download": 0, "rate_upload": 0,
                "peers_connected": 0, "upload_ratio": 0, "eta": -1, "download_dir": "/Downloads", "error_string": ""]
            return (200, [:], try Self.json(["result": ["torrents": [item]]]))
        }
        do { _ = try await client().removeAndConfirm(hashes: ["still-here"]); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("not confirmed")) }
    }
    func testCommandSelectionAndRightClickPreserveGroup() {
        var state = TorrentSelection()
        state.select("a", ordered: ["a", "b", "c"])
        state.select("b", ordered: ["a", "b", "c"], toggle: true)
        state.contextSelect("a", ordered: ["a", "b", "c"])
        XCTAssertEqual(state.ids, Set(["a", "b"]))
        XCTAssertEqual(state.primary, "a")
        state.contextSelect("c", ordered: ["a", "b", "c"])
        XCTAssertEqual(state.ids, Set(["c"]))
    }
    func testShiftSelectionAndRemovalReconciliation() {
        var state = TorrentSelection()
        state.select("b", ordered: ["a", "b", "c", "d"])
        state.select("d", ordered: ["a", "b", "c", "d"], extend: true)
        XCTAssertEqual(state.ids, Set(["b", "c", "d"]))
        state.retain(Set(["a", "c"]), ordered: ["a", "c"])
        XCTAssertEqual(state.ids, Set(["c"]))
        XCTAssertEqual(state.primary, "c")
        state.retain([], ordered: [])
        XCTAssertTrue(state.ids.isEmpty)
        XCTAssertNil(state.primary)
    }
    func testMultiSelectionActionSendsAllSelectedHashes() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            if body["method"] as? String == "session_get" { return (200, [:], try Self.json(["result": ["version": "4.1.0"]])) }
            XCTAssertEqual(body["method"] as? String, "torrent_stop")
            XCTAssertEqual((body["params"] as? [String: Any])?["ids"] as? [String], ["a", "b"])
            return (200, [:], try Self.json(["result": [:]]))
        }
        try await client().act(.stop, hashes: ["a", "b"])
    }

    func testAggregateProgressWeightsBySizeAndIncludesPausedTransfers() {
        var small = Torrent.examples[0]; small.totalSize = 100; small.percentDone = 1; small.status = 6
        var large = Torrent.examples[0]; large.totalSize = 900; large.percentDone = 0; large.status = 0
        XCTAssertEqual(Torrent.aggregateProgress([small, large]), 0.1, accuracy: 0.0001)
        large.percentDone = 0.5
        XCTAssertEqual(Torrent.aggregateProgress([small, large]), 0.55, accuracy: 0.0001)
        XCTAssertEqual(Torrent.aggregateProgress([]), 0)
        small.totalSize = 0
        XCTAssertEqual(Torrent.aggregateProgress([small]), 0)
    }

    func testModernSessionIdentityForEngineRecovery() async throws {
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            XCTAssertEqual(body["method"] as? String, "session_get")
            let fields = (body["params"] as? [String: Any])?["fields"] as? [String]
            let result: [String: Any] = fields == ["version"] ? ["version": "4.1.0"] : ["config_dir": "/Users/test/session"]
            return (200, [:], try Self.json(["result": result]))
        }
        let identity = try await client().sessionIdentity()
        XCTAssertEqual(identity, "/Users/test/session")
    }
    func testLegacySessionIdentityAndShutdown() async throws {
        var closed = false
        MockProtocol.handler = { request in
            let body = try Self.body(request)
            switch body["method"] as? String {
            case "session_get": return (200, [:], try Self.json(["result": "method name not recognized"]))
            case "session-close": closed = true; return (200, [:], try Self.json(["result": "success", "arguments": [:]]))
            default: return (200, [:], try Self.json(["result": "success", "arguments": ["config-dir": "/Users/test/session"]]))
            }
        }
        let rpc = try client()
        let identity = try await rpc.sessionIdentity()
        XCTAssertEqual(identity, "/Users/test/session")
        try await rpc.shutdown()
        XCTAssertTrue(closed)
    }
    func testMissingSessionIdentityCannotBeAccepted() async throws {
        MockProtocol.handler = { _ in (200, [:], try Self.json(["result": ["version": "4.1.0"]])) }
        do { _ = try await client().sessionIdentity(); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("identify")) }
    }

    func testBannerProgressFollowsSelectionAndReturnsToSession() {
        var a = Torrent.examples[0]; a.totalSize = 100; a.percentDone = 0.2
        var b = Torrent.examples[1]; b.totalSize = 900; b.percentDone = 0.8
        let all = Torrent.progressSummary([a, b], selectedIDs: [])
        XCTAssertEqual(all.value, 0.74, accuracy: 0.0001)
        XCTAssertEqual(all.label, "All torrents")
        let one = Torrent.progressSummary([a, b], selectedIDs: [a.id])
        XCTAssertEqual(one.value, 0.2, accuracy: 0.0001)
        XCTAssertTrue(one.label.contains(a.name))
        let both = Torrent.progressSummary([a, b], selectedIDs: [a.id, b.id])
        XCTAssertEqual(both.value, 0.74, accuracy: 0.0001)
        XCTAssertEqual(both.label, "Selected torrents (2)")
        let removed = Torrent.progressSummary([a, b], selectedIDs: ["no-longer-present"])
        XCTAssertEqual(removed.label, "All torrents")
    }
    func testFinderImportValidatesAndDeduplicatesFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("example.TORRENT")
        try Data("d4:infodee".utf8).write(to: file)
        XCTAssertEqual(try TorrentFileImport.validate([file, file]), [file])
        XCTAssertThrowsError(try TorrentFileImport.validate([folder]))
        XCTAssertThrowsError(try TorrentFileImport.validate([URL(string: "https://example.com/example.torrent")!]))
        let empty = folder.appendingPathComponent("empty.torrent")
        try Data().write(to: empty)
        XCTAssertThrowsError(try TorrentFileImport.validate([empty]))
    }

}
