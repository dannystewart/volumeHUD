//
//  VolumeHUDApp.swift
//  volumeHUD
//
//  Created by Danny Stewart on 9/21/25.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var volumeMonitor: VolumeMonitor!
    var hudController: HUDController!

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep app running even when main window is closed
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run in background without taking focus
        NSApplication.shared.setActivationPolicy(.accessory)

        // Initialize objects directly
        volumeMonitor = VolumeMonitor()
        hudController = HUDController()

        // Set up the connection between objects
        hudController.volumeMonitor = volumeMonitor
        volumeMonitor.hudController = hudController

        // Start monitoring volume changes
        volumeMonitor.startMonitoring()
        print("Started monitoring volume changes from AppDelegate")
    }
}

@main
@available(macOS 26.0, *)
struct VolumeHUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @available(macOS 26.0, *)
    var body: some Scene {
        // Create a hidden settings window that never shows
        Settings {
            EmptyView()
        }
        .windowResizability(.contentSize)
    }
}
