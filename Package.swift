// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoltaKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
    ],
    products: [
        .library(name: "MoltaKit", targets: ["MoltaKit"]),
    ],
    targets: [
        .target(name: "MoltaKit"),
        .testTarget(name: "MoltaKitTests", dependencies: ["MoltaKit"]),
    ]
)
