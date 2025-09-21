//
//  VolumeHUDApp.swift
//  Volume HUD
//
//  Created by Danny Stewart on 9/21/25.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var volumeMonitor: VolumeMonitor?
    var hudController: HUDController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep app running even when main window is closed
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start volume monitoring immediately (run silently in background)
        if let volumeMonitor = volumeMonitor, let hudController = hudController {
            volumeMonitor.startMonitoring()
            hudController.volumeMonitor = volumeMonitor
            volumeMonitor.hudController = hudController
            print("Started monitoring volume changes from AppDelegate")
        }
    }
}

@main
struct Volume_HUDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var volumeMonitor = VolumeMonitor()
    @StateObject private var hudController = HUDController()

    init() {
        // Keep app running in background even when windows are hidden
        NSApplication.shared.setActivationPolicy(.accessory)

        // Pass objects to app delegate for immediate initialization
        appDelegate.volumeMonitor = volumeMonitor
        appDelegate.hudController = hudController
    }

    var body: some Scene {
        // No main window - app runs silently in background
        Settings {
            EmptyView()
        }
    }
}
