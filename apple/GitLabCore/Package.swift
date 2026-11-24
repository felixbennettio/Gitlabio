// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitLabCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "GitLabCore", targets: ["GitLabCore"])],
    targets: [
        .target(name: "GitLabCore"),
        .testTarget(name: "GitLabCoreTests", dependencies: ["GitLabCore"])
    ]
)
