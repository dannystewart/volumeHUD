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
        .package(url: "https://github.com/dannystewart/polykit-swift.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "volumeHUD",
            dependencies: [
                .product(name: "PolyLog", package: "polykit-swift")
            ],
            path: "volumeHUD",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
