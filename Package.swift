// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "volumeHUD",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "volumeHUD",
            targets: ["volumeHUD"]
        )
    ],
    targets: [
        .executableTarget(
            name: "volumeHUD",
            path: "volumeHUD",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
