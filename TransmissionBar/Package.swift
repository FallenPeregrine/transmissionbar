// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TorrentBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TorrentBar", targets: ["TorrentBar"])],
    targets: [
        .target(name: "TorrentCore"),
        .executableTarget(name: "TorrentBar", dependencies: ["TorrentCore"]),
        .testTarget(name: "TorrentCoreTests", dependencies: ["TorrentCore"])
    ]
)
