import AppKit
import Darwin
import Polykit
import SwiftUI
@preconcurrency import UserNotifications

// MARK: - Launch Detection

private nonisolated func isManualLaunch(logger: PolyLog) -> Bool {
    // Check if launched by launchd (startup item) vs manually
    let parentPID = getppid()

    var name = [CChar](repeating: 0, count: 1024)
    let result = proc_name(parentPID, &name, UInt32(name.count))

    if result > 0 {
        // Build a String from the null-terminated C string buffer
        let parentName: String = name.withUnsafeBufferPointer { buffer in
            String(cString: buffer.baseAddress!)
        }

        logger.info("Parent process: \(parentName) (PID: \(parentPID))")

        // If parent is launchd, likely an auto-launch during startup
        let isLaunchdLaunch = parentName.contains("launchd")
        logger.info("Launch type: \(isLaunchdLaunch ? "automatic (launchd)" : "manual")")

        return !isLaunchdLaunch
    } else {
        logger.info("Failed to get parent process name (PID: \(parentPID)), assuming manual launch")
        return true // Default to manual if we can't determine
    }
}

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

        // Request notification permission and post "started" notification (only if manually launched)
        requestNotificationAuthorizationIfNeeded { [weak self] granted in
            guard let self else { return }
            if granted {
                // Only show startup notification if launched manually (not during system startup)
                if isManualLaunch(logger: logger) {
                    Task { @MainActor in
                        self.postUserNotification(title: "volumeHUD started!", body: nil)
                    }
                }
            }
        }

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

    private func requestNotificationAuthorizationIfNeeded(
        completion: @escaping @Sendable (Bool) -> Void,
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .denied:
                completion(false)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    completion(granted)
                }
            @unknown default:
                completion(false)
            }
        }
    }

    private func postUserNotification(title: String, body: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil,
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
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
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
        .windowResizability(.contentSize)
    }
}
