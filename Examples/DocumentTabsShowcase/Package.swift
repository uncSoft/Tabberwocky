// swift-tools-version: 5.9
import PackageDescription

// This example consumes Tabberwocky the same way an end user's app would — as a
// package dependency, built as a separate module (so `import Tabberwocky` is real
// and the library's `public` API boundary is enforced on every build).
//
// We use a LOCAL PATH dependency (`path: "../.."`) so it tracks the library source
// live while developing. A real app would instead use the released version:
//
//     .package(url: "https://github.com/uncSoft/Tabberwocky", from: "1.0.0")
//
// `build.sh` runs `swift build` and then wraps the produced binary into a proper
// .app bundle (Info.plist + document types + resources).
let package = Package(
    name: "DocumentTabsShowcase",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "DocumentTabsShowcase",
            dependencies: ["Tabberwocky"],
            path: "Sources"
        )
    ]
)
