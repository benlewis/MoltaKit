// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Set MOLTA_LIVE=1 in the build environment to compile the over-the-air
// downloader into the MoltaKit target (e.g. a release/TestFlight build that
// should keep pulling live assets). Unset → the downloader is compiled out.
let live = Context.environment["MOLTA_LIVE"] == "1"

let package = Package(
    name: "MoltaKit",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15)],
    products: [.library(name: "MoltaKit", targets: ["MoltaKit"])],
    targets: [
        .target(name: "MoltaKit", swiftSettings: live ? [.define("MOLTA_LIVE")] : []),
        .testTarget(name: "MoltaKitTests", dependencies: ["MoltaKit"]),
    ]
)
