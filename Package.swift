// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Nukku",
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
        .package(path: "Vendor/MediaRemoteAdapter")
    ],
    targets: [
        .executableTarget(
            name: "Nukku",
            dependencies: [
                .product(name: "MediaRemoteAdapter", package: "MediaRemoteAdapter")
            ],
            path: "Sources/Nukku",
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
