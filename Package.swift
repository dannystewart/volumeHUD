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
    dependencies: [
        .package(url: "git@github.com:dannystewart/PolyLog-Swift.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "volumeHUD",
            dependencies: ["PolyLog"],
            path: "volumeHUD",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
