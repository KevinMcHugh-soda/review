// swift-tools-version: 6.1
import PackageDescription

// Review — a native macOS app for reviewing pull requests.
//
// Layering rule: every target below `ReviewApp`/`review` is pure logic with
// no SwiftUI and no AppKit, so the hard parts (diff mapping, the LSP client,
// the GitHub and Claude bridges, storage) are testable with `swift test`
// without launching a GUI, and so the app and the CLI share one core.
// `make check` enforces this mechanically — see the lint-layers target.
//
// Targets are added milestone by milestone; plans/architecture.md has the
// full planned graph.
let package = Package(
    name: "Review",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        // The bundle is Review.app, but the executable inside it is named
        // ReviewApp. macOS filesystems are case-insensitive by default, so an
        // app binary named `Review` and a CLI binary named `review` would be
        // the same file in the build directory and inside Contents/MacOS.
        .executable(name: "ReviewApp", targets: ["ReviewApp"]),
        .executable(name: "review", targets: ["review"]),
        .library(name: "ReviewKit", targets: ["ReviewKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
    ],
    targets: [
        // Pure logic.
        .target(name: "ReviewCore"),
        // Child processes: git, gh, the language servers and claude all run
        // as subprocesses, with the user's login-shell environment.
        .target(name: "ReviewProcess"),
        // The facade both frontends consume. Still no SwiftUI.
        .target(name: "ReviewKit", dependencies: ["ReviewCore", "ReviewProcess"]),

        // Frontends.
        .executableTarget(
            name: "ReviewApp",
            dependencies: ["ReviewKit", "ReviewCore", "ReviewProcess"],
            path: "Sources/ReviewApp"
        ),
        .executableTarget(
            name: "review",
            dependencies: [
                "ReviewKit", "ReviewCore", "ReviewProcess",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ReviewCLI"
        ),

        // Tests.
        .testTarget(name: "ReviewCoreTests", dependencies: ["ReviewCore"]),
        .testTarget(name: "ReviewProcessTests", dependencies: ["ReviewProcess"]),
    ],
    swiftLanguageModes: [.v6]
)
