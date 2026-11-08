// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BetterApple",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BetterAppleCore", targets: ["BetterAppleCore"]),
               .executable(name: "BetterApple", targets: ["BetterApple"])],
    targets: [
        .target(name: "BetterAppleCore"),
        .executableTarget(name: "BetterApple", dependencies: ["BetterAppleCore"], exclude: ["Services/README.md"]),
        .testTarget(name: "BetterAppleCoreTests", dependencies: ["BetterAppleCore"])
    ]
)
