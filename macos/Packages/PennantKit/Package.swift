// swift-tools-version: 6.2
// PennantKit: what the Mac app knows how to do apart from drawing (SWIFTUI_REBUILD.md section 6). It starts and
// watches the server (`ServerController`), talks to it through the generated client (PennantAPI), listens to its
// events, and holds the app's state (`AppModel`), the routes, the unknown-last comparator and the first-run backup.
// It decides no baseball question: every judgment and sentence it passes on is the server's.
import PackageDescription

/// Swift 6 with Approachable Concurrency. The package keeps Swift's default (nonisolated) isolation: it holds an
/// actor, value types and protocols used from both sides; `AppModel` is `@MainActor` by name.
let concurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "PennantKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PennantKit", targets: ["PennantKit"]),
    ],
    dependencies: [
        .package(path: "../PennantAPI"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.12.1"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.3.1"),
    ],
    targets: [
        .target(
            name: "PennantKit",
            dependencies: [
                .product(name: "PennantAPI", package: "PennantAPI"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            swiftSettings: concurrency
        ),
        .testTarget(
            name: "PennantKitTests",
            dependencies: [
                "PennantKit",
                .product(name: "PennantAPI", package: "PennantAPI"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            swiftSettings: concurrency
        ),
    ],
    swiftLanguageModes: [.v6]
)
