// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mumble",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Local Parakeet recognition through FluidAudio. Apple Speech remains the default
        // and needs no bundled model.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")
    ],
    targets: [
        // Keep lexicon behavior independent so its contract is cheap to test.
        .target(
            name: "MumbleDictionary",
            path: "kit/dictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Mumble",
            dependencies: [
                "MumbleDictionary",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "app",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "MumbleDictionaryTests",
            dependencies: ["MumbleDictionary"],
            path: "qa/dictionary",
            resources: [.copy("lexicon-contract.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
