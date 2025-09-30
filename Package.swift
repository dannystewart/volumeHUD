// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "volumeHUD",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(
            name: "volumeHUD",
            targets: ["volumeHUD"]
        ),
    ],
    dependencies: [
        .package(path: "../polykit-swift"),
    ],
    targets: [
        .executableTarget(
            name: "volumeHUD",
            dependencies: [
                .product(name: "Polykit", package: "polykit-swift"),
            ],
            path: "volumeHUD",
            resources: [
                .process("Assets.xcassets"),
                .process("volumeHUD.entitlements"),
            ]
        ),
    ]
)
