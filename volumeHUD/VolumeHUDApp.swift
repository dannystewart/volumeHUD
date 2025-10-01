import AppKit
import Polykit
import SwiftUI

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var volumeMonitor: VolumeMonitor!
    var brightnessMonitor: BrightnessMonitor!
    var hudController: HUDController!
    var aboutWindow: NSWindow?

    let logger = PolyLog()

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        // If about window closes, switch back to accessory mode
        if aboutWindow?.isVisible == false {
            NSApp.setActivationPolicy(.accessory)
        }
        return false // Keep app running even when windows are closed
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Keep the app headless and out of the Dock
        NSApplication.shared.setActivationPolicy(.accessory)

        // Initialize the monitors and HUD controller
        volumeMonitor = VolumeMonitor()
        brightnessMonitor = BrightnessMonitor()
        hudController = HUDController()

        // Set up bidirectional references
        hudController.volumeMonitor = volumeMonitor
        hudController.brightnessMonitor = brightnessMonitor
        volumeMonitor.hudController = hudController
        brightnessMonitor.hudController = hudController

        // Start monitoring volume changes
        volumeMonitor.startMonitoring()
        brightnessMonitor.startMonitoring()

        // Start monitoring display configuration changes
        hudController.startDisplayChangeMonitoring()
    }

    // Handle attempts to launch the app a second time
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        // Show the about window instead of quitting
        showAboutWindow()
        return false
    }

    // If we get a new "open" event, also show the about window
    func application(_: NSApplication, open _: [URL]) {
        showAboutWindow()
    }

    private func showAboutWindow() {
        // If window already exists and is visible, just bring it to front
        if let window = aboutWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create the about window
        let aboutView = AboutView { [weak self] in
            self?.aboutWindow?.close()
            self?.aboutWindow = nil
            self?.gracefulTerminate()
        }

        let hostingController = NSHostingController(rootView: aboutView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )

        window.contentViewController = hostingController
        window.title = "About volumeHUD"

        // Position at visual center of the screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 280
            let windowHeight: CGFloat = 360

            let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
            let y = screenFrame.origin.y + screenFrame.height * 0.66 - windowHeight / 2

            window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: false)
        }

        window.isReleasedWhenClosed = false

        aboutWindow = window

        // Temporarily switch to regular app to show window properly
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func gracefulTerminate() {
        logger.info("Stopping monitoring and quitting.")
        volumeMonitor?.stopMonitoring()
        brightnessMonitor?.stopMonitoring()
        hudController?.stopDisplayChangeMonitoring()

        // Terminate without activating the app
        NSApp.terminate(nil)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
}

// MARK: - VolumeHUDApp

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
