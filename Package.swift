// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SynthezKit",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "SynthezCore", targets: ["SynthezCore"]),
        .library(name: "SynthezWidgets", targets: ["SynthezWidgets"]),
        .library(name: "SynthezKit", targets: ["SynthezKit"]),
        .library(name: "SynthezGallery", targets: ["SynthezGallery"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Lakr233/DisplayLink.git", from: "3.0.1"),
    ],
    targets: [
        .target(
            name: "SynthezCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
        ),
        .target(
            name: "SynthezWidgets",
            dependencies: ["SynthezCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
        ),
        .target(
            name: "SynthezKit",
            dependencies: [
                "SynthezCore",
                .product(name: "DisplayLink", package: "DisplayLink"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
        ),
        .target(
            name: "SynthezGallery",
            dependencies: ["SynthezCore", "SynthezWidgets"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
        ),
        .executableTarget(
            name: "SynthezBench",
            dependencies: ["SynthezCore", "SynthezWidgets", "SynthezGallery"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
        ),
        .testTarget(
            name: "SynthezCoreTests",
            dependencies: ["SynthezCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
        ),
        .testTarget(
            name: "SynthezWidgetsTests",
            dependencies: ["SynthezCore", "SynthezWidgets", "SynthezGallery"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
        ),
    ],
    swiftLanguageModes: [.v6],
)
