// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipTen",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClipTen", targets: ["ClipTen"])],
    targets: [
        .target(name: "ClipTenCore"),
        .executableTarget(name: "ClipTen", dependencies: ["ClipTenCore"]),
        .testTarget(name: "ClipTenCoreTests", dependencies: ["ClipTenCore"]),
        .testTarget(name: "ClipTenTests", dependencies: ["ClipTen", "ClipTenCore"])
    ]
)
