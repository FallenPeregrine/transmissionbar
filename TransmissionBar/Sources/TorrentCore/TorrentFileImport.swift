import Foundation

public enum TorrentFileImport {
    public static func validate(_ urls: [URL]) throws -> [URL] {
        var seen = Set<URL>()
        var files: [URL] = []
        for url in urls {
            guard url.isFileURL, url.pathExtension.lowercased() == "torrent" else {
                throw RPCError.message("Open a local .torrent file with TransmissionBar.")
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { throw RPCError.message("Choose a torrent file, not a folder.") }
            guard let size = values.fileSize, size > 0, size <= 20 * 1024 * 1024 else {
                throw RPCError.message("Torrent files must be nonempty and no larger than 20 MB.")
            }
            if seen.insert(url.standardizedFileURL.resolvingSymlinksInPath()).inserted { files.append(url) }
        }
        return files
    }
}
