// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenLab",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TokenLab", targets: ["TokenLabApp"])],
    targets: [
        .target(name: "TokenLabCore"),
        .executableTarget(name: "TokenLabApp", dependencies: ["TokenLabCore"]),
        .testTarget(name: "TokenLabCoreTests", dependencies: ["TokenLabCore"])
    ]
)
