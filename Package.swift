// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tabberwocky",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Tabberwocky", targets: ["Tabberwocky"]),
    ],
    targets: [
        .target(name: "Tabberwocky", path: "Sources/Tabberwocky"),
        .testTarget(name: "TabberwockyTests", dependencies: ["Tabberwocky"],
                    path: "Tests/TabberwockyTests"),
    ]
)
