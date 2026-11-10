import AppKit
import Darwin
import TorrentCore

@MainActor
final class LocalEngine {
    private var process: Process?
    private var adopted = false
    private var lockFD: Int32 = -1
    private var log: FileHandle?
    private var rpc: TransmissionClient?
    private(set) var password = ""
    let endpoint = "http://localhost:9093/transmission/rpc"
    var isRunning: Bool { process?.isRunning == true || adopted }
    private var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TorrentBar/BundledTransmission")
    }
    private func error(_ text: String) -> Error {
        NSError(domain: "TransmissionBar", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private func sameDirectory(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath() == directory.standardizedFileURL.resolvingSymlinksInPath()
    }
    private func pause() async {
        // Also yield during cancellation while waiting for graceful engine shutdown.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { continuation.resume() }
        }
    }
    func start() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        lockFD = open(directory.appendingPathComponent("app.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
            if lockFD >= 0 { close(lockFD); lockFD = -1 }
            throw error("Another TransmissionBar instance is using this session. Quit it before opening this copy.")
        }
        _ = fcntl(lockFD, F_SETFD, FD_CLOEXEC)
        do {
            let secretURL = directory.appendingPathComponent("rpc-password")
            if fm.fileExists(atPath: secretURL.path) {
                password = try String(contentsOf: secretURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !password.isEmpty else { throw error("The saved local engine credential is empty. No torrent data was changed.") }
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretURL.path)
            } else {
                password = UUID().uuidString + UUID().uuidString
                // Create with restrictive permissions from the outset.
                guard fm.createFile(atPath: secretURL.path, contents: Data(password.utf8), attributes: [.posixPermissions: 0o600]) else {
                    throw error("Could not save the local engine credential.")
                }
            }
            let connection = try Connection(endpoint: endpoint, username: "torrentbar", password: password)
            let client = TransmissionClient(connection: connection, timeout: 1)
            rpc = client
            do {
                let identity = try await client.sessionIdentity()
                try Task.checkCancellation()
                guard sameDirectory(identity) else { throw error("Port 9093 belongs to a different Transmission session. That session was left untouched.") }
                // A previous app crash can leave the engine alive. Reuse it only
                // after authenticating and matching its exact state directory.
                adopted = true
                return
            } catch RPCError.unavailable(_) { // No listener, as reported by the RPC transport.
            } catch let failure as URLError where [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost].contains(failure.code) {
                // No reachable server: launch our bundled engine below.
            } catch is CancellationError { throw CancellationError() }
            catch {
                throw self.error("An existing service on port 9093 could not be verified as this app's engine. A leftover engine from an older build may have a different password. Quit the older copy and check the listener before retrying. No existing service was stopped. Details: \(error.localizedDescription)")
            }
            try Task.checkCancellation()
            let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/transmission-daemon")
            guard fm.isExecutableFile(atPath: executable.path) else { throw error("The bundled engine is missing. Rebuild the app.") }
            let logURL = directory.appendingPathComponent("engine.log")
            if !fm.fileExists(atPath: logURL.path) { fm.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            log = try FileHandle(forWritingTo: logURL); try log?.seekToEnd()
            let child = Process(); child.executableURL = executable
            child.arguments = ["--foreground", "--config-dir", directory.path,
                "--rpc-bind-address", "127.0.0.1", "--port", "9093", "--allowed", "127.0.0.1",
                "--auth", "--username", "torrentbar", "--password", password]
            if !fm.fileExists(atPath: directory.appendingPathComponent("settings.json").path) {
                child.arguments! += ["--peerport", "51415", "--download-dir", fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path]
            }
            child.standardOutput = log; child.standardError = log
            try child.run(); process = child
            var lastError: Error?
            for _ in 0..<40 {
                try Task.checkCancellation()
                guard child.isRunning else { throw error("The engine exited during startup. Open the engine log in Application settings for details.") }
                do {
                    let identity = try await client.sessionIdentity()
                    guard sameDirectory(identity), child.isRunning else { throw error("The running engine's identity could not be verified.") }
                    return
                } catch { lastError = error }
                await pause()
            }
            throw error("The engine did not become ready. \(lastError?.localizedDescription ?? "Check the engine log.")")
        } catch {
            // Only a child we launched can be terminated here.
            if let process, process.isRunning {
                process.terminate()
                for _ in 0..<200 { if !process.isRunning { break }; await pause() }
            }
            if process?.isRunning != true { releaseLock() }
            throw error
        }
    }
    func stop() async throws {
        if let process, process.isRunning {
            process.terminate()
            for _ in 0..<200 { if !process.isRunning { break }; await pause() }
            guard !process.isRunning else { throw error("The engine is still saving its session. Wait a moment and quit again.") }
        } else if adopted, let rpc {
            // Ownership was authenticated and directory-checked during start().
            do { try await rpc.shutdown() }
            catch RPCError.unavailable(_) { adopted = false; releaseLock(); return }
            catch let failure as URLError where [.networkConnectionLost, .cannotConnectToHost].contains(failure.code) {} // Engine can close before replying.
            for _ in 0..<200 {
                do { _ = try await rpc.sessionIdentity() }
                catch RPCError.unavailable(_) { adopted = false; releaseLock(); return }
                catch let failure as URLError where [.cannotConnectToHost, .networkConnectionLost].contains(failure.code) {
                    adopted = false; releaseLock(); return
                }
                catch { throw error }
                await pause()
            }
            throw error("The recovered engine has not finished shutting down. Wait and quit again.")
        }
        adopted = false; releaseLock()
    }
    private func releaseLock() {
        try? log?.close(); log = nil
        if lockFD >= 0 { _ = flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1 }
    }
}
