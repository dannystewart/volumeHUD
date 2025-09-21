// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Volume HUD",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "Volume HUD",
            targets: ["Volume HUD"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Volume HUD",
            path: "Volume HUD",
            sources: [
                "ContentView.swift",
                "HUDController.swift",
                "VolumeHUDApp.swift",
                "VolumeHUDView.swift",
                "VolumeMonitor.swift",
            ]
        )
    ]
)
