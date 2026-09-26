// swift-tools-version: 6.2
// PennantDesign: how the Mac app draws what the server says (SWIFTUI_REBUILD.md section 6): claims, glass, charts,
// club theming and tone colours. At N3 it holds only club colour reading; the components arrive with N5.
import PackageDescription

let package = Package(
    name: "PennantDesign",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PennantDesign", targets: ["PennantDesign"]),
    ],
    targets: [
        .target(
            name: "PennantDesign",
            swiftSettings: [
                // Views: the app's own isolation (MainActor by default) and Approachable Concurrency
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "PennantDesignTests",
            dependencies: ["PennantDesign"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
