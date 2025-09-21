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
                "Volume_HUDApp.swift",
                "ContentView.swift",
                "VolumeMonitor.swift",
                "HUDController.swift",
                "VolumeHUDView.swift",
            ]
        )
    ]
)
