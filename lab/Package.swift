// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MumbleSignalLab",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")
    ],
    targets: [
        .executableTarget(
            name: "mumble-signal-lab",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "runner"
        )
    ]
)
