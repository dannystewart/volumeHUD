import AppKit
import Darwin
import Foundation
import Polykit
import SwiftUI
@preconcurrency import UserNotifications

// MARK: - Launch Detection

private nonisolated func isManualLaunch(logger: PolyLog) -> Bool {
    // Check if we're running in test environment or SwiftUI preview mode
    if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || NSClassFromString("XCTest") != nil {
        logger.debug("Running in test environment or SwiftUI preview.")
        return false
    }

    // Check if we're running from Xcode preview process
    let processName = ProcessInfo.processInfo.processName
    if processName.contains("XCPreviewAgent") || processName.contains("PreviewHost") {
        logger.debug("Running in Xcode preview process: \(processName)")
        return false
    }

    // Check if launched by launchd (startup item) or manually
    let parentPID = getppid()

    var name = [CChar](repeating: 0, count: 1024)
    let result = proc_name(parentPID, &name, UInt32(name.count))

    if result > 0 {
        // Build a String from the null-terminated C string buffer
        let parentName: String = name.withUnsafeBufferPointer { buffer in
            String(cString: buffer.baseAddress!)
        }

        logger.debug("Parent process: \(parentName) (PID: \(parentPID))")

        // If parent is launchd, likely an auto-launch during startup
        let isLaunchdLaunch = parentName.contains("launchd")
        logger.info("Launch type: \(isLaunchdLaunch ? "automatic (launchd)" : "manual")")

        return !isLaunchdLaunch
    } else {
        logger.info("Failed to get parent process name (PID: \(parentPID)), assuming manual launch.")
        return true // Default to manual if we can't determine
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    var volumeMonitor: VolumeMonitor!
    var brightnessMonitor: BrightnessMonitor!
    var hudController: HUDController!
    var aboutWindow: NSPanel?

    let logger = PolyLog()

    /// Set to true to bypass accessibility checks for debugging
    let shouldBypassAccessibility = false

    func applicationDidFinishLaunching(_: Notification) {
        // Skip full initialization if running in SwiftUI preview or test mode
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
            NSClassFromString("XCTest") != nil ||
            ProcessInfo.processInfo.processName.contains("XCPreviewAgent") ||
            ProcessInfo.processInfo.processName.contains("PreviewHost")
        {
            logger.debug("Skipping app initialization for test environment or SwiftUI preview.")
            return
        }

        // Keep the app headless and out of the Dock
        NSApplication.shared.setActivationPolicy(.accessory)

        // Set up the notifications delegate BEFORE scheduling any notifications
        UNUserNotificationCenter.current().delegate = self

        // Initialize the monitors and HUD controller
        volumeMonitor = VolumeMonitor()
        brightnessMonitor = BrightnessMonitor()
        hudController = HUDController()

        // Set up bidirectional references
        hudController.volumeMonitor = volumeMonitor
        hudController.brightnessMonitor = brightnessMonitor
        volumeMonitor.hudController = hudController
        brightnessMonitor.hudController = hudController
        brightnessMonitor.accessibilityBypassed = shouldBypassAccessibility

        // Include warning in startup message if we're bypassing accessibility
        let notificationText =
            if brightnessMonitor.accessibilityBypassed == true {
                "volumeHUD started (accessibility bypassed)"
            } else {
                "volumeHUD started!"
            }

        // Request notification permission and post "started" notification (only if manually launched)
        requestNotificationAuthorizationIfNeeded { [weak self] granted in
            guard let self else { return }
            logger.debug("Notification permission granted: \(granted)")
            if granted {
                // Only show startup notification if launched manually (not during system startup)
                if isManualLaunch(logger: logger) {
                    Task { @MainActor in
                        self.postUserNotification(title: notificationText, body: nil)
                    }
                } else {
                    logger.info("Skipping startup notification due to automatic launch.")
                }
            } else {
                logger.info("No notification permission; skipping startup notification.")
            }
        }

        // Start monitoring volume changes (always enabled)
        volumeMonitor.startMonitoring()

        // Start brightness monitoring only if enabled in settings
        if UserDefaults.standard.bool(forKey: "brightnessEnabled") {
            logger.info("Brightness HUD enabled; starting brightness monitoring.")
            brightnessMonitor.startMonitoring()
        } else {
            logger.info("Brightness HUD disabled; skipping brightness monitoring.")
        }

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
            return
        }

        // Create the about window
        let aboutView = AboutView(onQuit: { [weak self] in
            self?.aboutWindow?.close()
            self?.aboutWindow = nil
            self?.gracefulTerminate()
        }, appDelegate: self)

        let hostingController = NSHostingController(rootView: aboutView)

        // Use NSPanel to remain in accessory mode
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )

        panel.contentViewController = hostingController
        panel.title = "About volumeHUD"

        // Position at visual center of the screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 280
            let windowHeight: CGFloat = 450

            let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
            let y = screenFrame.origin.y + screenFrame.height * 0.66 - windowHeight / 2

            panel.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: false)
        }

        panel.isReleasedWhenClosed = false

        aboutWindow = panel

        // Show the panel without changing activation policy
        panel.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func updateBrightnessMonitoring() {
        if UserDefaults.standard.bool(forKey: "brightnessEnabled") {
            logger.info("Enabling brightness HUD; starting brightness monitoring.")
            brightnessMonitor.startMonitoring()
        } else {
            logger.info("Disabling brightness HUD; stopping brightness monitoring.")
            brightnessMonitor.stopMonitoring()
        }
    }

    private func gracefulTerminate() {
        logger.info("Stopping monitoring and quitting.")
        volumeMonitor?.stopMonitoring()
        // Only stop brightness monitoring if it was started
        if UserDefaults.standard.bool(forKey: "brightnessEnabled") {
            brightnessMonitor?.stopMonitoring()
        }
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
                center.requestAuthorization(options: [.alert]) { granted, _ in
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

        UNUserNotificationCenter.current().add(request) { error in
            if let error { self.logger.warning("Failed to post notification: \(error)") }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Ensure banners appear even if the app is active
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner])
    }

    // Handle notification taps
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive _: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        // Show the about window when the startup notification is tapped
        Task { @MainActor in
            self.showAboutWindow()
        }
        completionHandler()
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
