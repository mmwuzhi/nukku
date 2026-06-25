// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Nukku",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Nukku", targets: ["Nukku"])
    ],
    dependencies: [
        // Vendored fork of github.com/ejbills/mediaremote-adapter
        // (rev cf30c4f). Patched so run.pl resolves from the host app's Resources,
        // making the packaged .app self-contained. See Vendor/MediaRemoteAdapter.
        .package(path: "Vendor/MediaRemoteAdapter"),
        // Private SkyLight APIs to float the notch panel above native full-screen
        // apps (no public API can do this). MIT-licensed, pure Swift (no resources).
        .package(url: "https://github.com/Lakr233/SkyLightWindow", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Nukku",
            dependencies: [
                .product(name: "MediaRemoteAdapter", package: "MediaRemoteAdapter"),
                .product(name: "SkyLightWindow", package: "SkyLightWindow"),
            ],
            path: "Sources/Nukku",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "NukkuTests",
            dependencies: ["Nukku"],
            path: "Tests/NukkuTests"
        )
    ]
)
