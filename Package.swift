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
    targets: [
        .executableTarget(
            name: "Nukku",
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
