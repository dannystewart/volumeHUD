//
//  VolumeHUDApp.swift
//  by Danny Stewart (2025)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import AppKit
import Darwin
import Foundation
import PolyKit
import SwiftUI
@preconcurrency import UserNotifications

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    /// Constants for process path info
    private nonisolated static let PROC_PIDPATHINFO_MAXSIZE = 4096

    // MARK: - Launch Detection

    /// Shared UserDefaults key for login helper launch marker (must match LoginHelper)
    private nonisolated static let launchMarkerKey = "loginHelperLaunchTimestamp"

    /// Maximum age of the launch marker to consider it valid (10 seconds)
    private nonisolated static let launchMarkerMaxAge: TimeInterval = 10.0

    /// Maximum system uptime to consider as "just logged in" (3 minutes)
    private nonisolated static let loginUptimeThreshold: TimeInterval = 180.0

    var volumeMonitor: VolumeMonitor!
    var brightnessMonitor: BrightnessMonitor!
    var hudController: HUDController!
    var mediaKeyInterceptor: MediaKeyInterceptor?
    var aboutWindow: NSPanel?
    var loginItemManager: LoginItemManager!

    let logger: PolyLog = .init()

    /// Check to see if brightness is enabled
    private var isBrightnessEnabled: Bool {
        UserDefaults.standard.bool(forKey: "brightnessEnabled")
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - On Finish Launching

    func applicationDidFinishLaunching(_: Notification) {
        // Skip full initialization if running in SwiftUI preview or test mode
        let isDevEnvironment = isRunningInDevEnvironment()
        if isDevEnvironment { return }

        // Check for other instances running from different bundle paths
        if let otherInstancePath = checkForOtherInstances() {
            showConflictingInstanceAlert(otherPath: otherInstancePath)
            // Exit after showing the alert
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
            return
        }

        // Keep the app headless and out of the Dock
        NSApplication.shared.setActivationPolicy(.accessory)

        // Set up the notifications delegate BEFORE scheduling any notifications
        UNUserNotificationCenter.current().delegate = self

        // Initialize login item manager, monitors, and HUD controller
        loginItemManager = LoginItemManager()
        volumeMonitor = VolumeMonitor(isPreviewMode: false)
        brightnessMonitor = BrightnessMonitor(isPreviewMode: false)
        hudController = HUDController(isPreviewMode: false)

        // Set up bidirectional references
        hudController.volumeMonitor = volumeMonitor
        hudController.brightnessMonitor = brightnessMonitor
        volumeMonitor.hudController = hudController
        brightnessMonitor.hudController = hudController

        // Request accessibility permissions if needed
        requestAccessibilityPermissionsIfNeeded()

        // Request notification permission and post "started" notification (only if manually launched)
        requestNotificationAuthorizationIfNeeded { [weak self] granted in
            guard let self else { return }
            logger.debug("Notification permission granted: \(granted)")
            if granted {
                // Only show startup notification if launched manually (not during system startup)
                if isManualLaunch() {
                    Task { @MainActor in
                        self.postUserNotification(title: "volumeHUD started!", body: nil)
                    }
                } else {
                    logger.info("Skipping startup notification due to automatic launch.")
                }
            } else {
                logger.info("No notification permission; skipping startup notification.")
            }
        }

        // Start monitoring volume changes
        volumeMonitor.startMonitoring()

        // Start brightness monitoring only if enabled in settings
        startBrightnessMonitoringIfEnabled()

        // Start media key interceptor to hide system HUDs
        startMediaKeyInterceptor()

        // Start monitoring display configuration changes
        hudController.startDisplayChangeMonitoring()
    }

    /// If we get a new "open" event, also show the about window
    func application(_: NSApplication, open _: [URL]) {
        showAboutWindow()
    }

    /// Open the about window when the app is opened while already running
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showAboutWindow()
        return false
    }

    @MainActor
    func startBrightnessMonitoringIfEnabled() {
        if isBrightnessEnabled {
            logger.info("Brightness HUD enabled; starting brightness monitoring.")
            brightnessMonitor.startMonitoring()
        } else {
            logger.info("Brightness HUD disabled; skipping brightness monitoring.")
        }
    }

    /// Start the media key interceptor to hide system HUDs.
    /// The interceptor automatically falls back to system HUDs if interception fails.
    @MainActor
    func startMediaKeyInterceptor() {
        // Create the interceptor if not already created
        if mediaKeyInterceptor == nil {
            mediaKeyInterceptor = MediaKeyInterceptor()
            mediaKeyInterceptor?.hudController = hudController
        }

        if mediaKeyInterceptor?.start() == true {
            logger.info("Media key interceptor started.")
        } else {
            logger.warning("Failed to start media key interceptor. Accessibility permissions may be required.")
        }
    }

    // MARK: - Notification Center Delegate

    /// Ensure banners appear even if the app is active
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler:
        @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner])
    }

    /// Show the About window when the startup notification is tapped
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive _: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        Task { @MainActor in self.showAboutWindow() }
        completionHandler()
    }

    // MARK: - Instance Check

    /// Checks if there's another instance of volumeHUD running from a different bundle path.
    /// Returns the path of the other instance if found, nil otherwise.
    private nonisolated func checkForOtherInstances() -> String? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentBundlePath = Bundle.main.bundlePath

        // Use `pgrep` to find all processes with "volumeHUD" in the name
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "volumeHUD"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Suppress errors

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let pids = output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

            // Check each PID to see if it's from a different bundle path
            for pid in pids {
                if pid == currentPID { continue }

                if let bundlePath = getBundlePath(for: pid) {
                    // Found another instance with a different bundle path
                    if bundlePath != currentBundlePath {
                        return bundlePath
                    }
                }
            }
        } catch {
            logger.warning("Failed to check for other instances: \(error)")
        }

        return nil
    }

    /// Gets the bundle path for a given process ID.
    private nonisolated func getBundlePath(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(Self.PROC_PIDPATHINFO_MAXSIZE))
        let result = proc_pidpath(pid, &pathBuffer, UInt32(Self.PROC_PIDPATHINFO_MAXSIZE))

        guard result > 0 else { return nil }

        // Find the null terminator and convert to UInt8
        let pathLength = pathBuffer.firstIndex(of: 0) ?? pathBuffer.count
        let utf8Bytes = pathBuffer[..<pathLength].map { UInt8(bitPattern: $0) }
        let executablePath = String(decoding: utf8Bytes, as: UTF8.self)

        // Extract bundle path from executable path
        if let appRange = executablePath.range(of: ".app/") {
            return String(executablePath[..<appRange.upperBound].dropLast(1))
        }

        return nil
    }

    /// Shows an alert when a conflicting instance is detected.
    private func showConflictingInstanceAlert(otherPath: String) {
        let alert = NSAlert()
        alert.messageText = "Another volumeHUD Instance Detected"
        alert.informativeText = """
        Another copy of volumeHUD is already running from a different location:

        \(otherPath)

        This instance will now exit. Please quit the other instance first if you want to run this version instead.

        Tip: Use 'pkill -f volumeHUD' in Terminal to stop all instances.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        // Temporarily show app in dock for the alert
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Environment Check

    /// Check to see if we're running in a development environment (SwiftUI preview, test mode, etc.)
    private nonisolated func isRunningInDevEnvironment() -> Bool {
        if
            ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
            NSClassFromString("XCTest") != nil ||
            ProcessInfo.processInfo.processName.contains("XCPreviewAgent") ||
            ProcessInfo.processInfo.processName.contains("PreviewHost")
        {
            return true
        }

        return false
    }

    /// Returns true if this was a manual launch (user double-clicked), false for automatic (login item).
    private nonisolated func isManualLaunch() -> Bool {
        if isRunningInDevEnvironment() { return false }

        // Check 1: UserDefaults marker from LoginHelper (most reliable)
        // LoginHelper writes a timestamp just before launching us
        if let markerTimestamp = UserDefaults.standard.object(forKey: Self.launchMarkerKey) as? TimeInterval {
            let markerAge = Date().timeIntervalSince1970 - markerTimestamp
            // Clear the marker so it doesn't affect future launches
            UserDefaults.standard.removeObject(forKey: Self.launchMarkerKey)
            UserDefaults.standard.synchronize()

            if markerAge < Self.launchMarkerMaxAge {
                logger.debug("Launch detected via UserDefaults marker (age: \(String(format: "%.1f", markerAge))s)")
                return false // Launched by login helper
            }
        }

        // Check 2: System uptime heuristic
        // If the system just booted (uptime < 3 minutes), likely a login item launch
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime < Self.loginUptimeThreshold {
            logger.debug("Launch detected via system uptime heuristic (uptime: \(String(format: "%.0f", uptime))s)")
            return false // Likely launched at login
        }

        // Check 3: Legacy checks for backwards compatibility
        if CommandLine.arguments.contains("--launchedByLoginItem") { return false }
        if ProcessInfo.processInfo.environment["VOLUMEHUD_LOGIN_HELPER"] == "1" { return false }

        // Check 4: Parent process checks (less reliable but kept as fallback)
        let parentPID = getppid()
        if isParentEmbeddedLoginHelper(parentPID) { return false }

        // Default to manual launch
        logger.debug("Manual launch detected (uptime: \(String(format: "%.0f", uptime))s)")
        return true
    }

    /// Checks if the parent PID is our embedded login helper in Contents/Library/LoginItems.
    private nonisolated func isParentEmbeddedLoginHelper(_ parentPID: pid_t) -> Bool {
        guard let parentBundlePath = getBundlePath(for: parentPID) else { return false }

        let loginItemsURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems", isDirectory: true)

        var isDir: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: loginItemsURL.path, isDirectory: &isDir),
            isDir.boolValue else
        {
            return false
        }

        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: loginItemsURL,
                includingPropertiesForKeys: nil,
            ) else
        {
            return false
        }

        return contents.contains { $0.pathExtension == "app" && $0.path == parentBundlePath }
    }

    // MARK: - Show About Window

    private func showAboutWindow() {
        // If window already exists and is visible, just bring it to the front
        if let window = aboutWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Create the About window
        let aboutView = AboutView(
            onQuit: { [weak self] in
                self?.aboutWindow?.close()
                self?.aboutWindow = nil
                self?.gracefulTerminate()
            },
            appDelegate: self,
            loginItemManager: loginItemManager,
        )

        let hostingController = NSHostingController(rootView: aboutView)

        // Use NSPanel to remain in accessory mode
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )

        panel.contentViewController = hostingController
        panel.title = "About volumeHUD"

        // Prevent the panel from closing when clicking away
        panel.hidesOnDeactivate = false

        // Position at visual center of the screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 600
            let windowHeight: CGFloat = 300

            let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
            let y = screenFrame.origin.y + screenFrame.height * 0.66 - windowHeight / 2

            panel.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: false)
        }

        panel.isReleasedWhenClosed = false

        aboutWindow = panel

        // Show the panel without changing activation policy
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Accessibility Permissions

    private nonisolated func requestAccessibilityPermissionsIfNeeded() {
        // Check current permission status
        let isCurrentlyTrusted = AXIsProcessTrusted()

        // If already trusted, no need to prompt
        if isCurrentlyTrusted {
            logger.info("Accessibility permissions already granted.")
            return
        }

        // If not trusted, request with prompt.
        logger.info("Prompting/checking for accessibility permissions.")

        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as [String: Bool] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Update accessibility status after the request
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 500000000) // 0.5 second delay
            let newStatus = AXIsProcessTrusted()
            updateAccessibilityStatus()

            if newStatus {
                logger.info("Accessibility permissions granted! Key press monitoring will be more reliable.")
            } else {
                logger.info("Accessibility permissions not yet enabled. Key press monitoring will be limited.")
                logger.info("To enable: System Settings → Privacy & Security → Accessibility")
            }
        }
    }

    @MainActor
    private func updateAccessibilityStatus() {
        // Update both monitors' accessibility status centrally
        brightnessMonitor.updateAccessibilityStatus()
        volumeMonitor.updateAccessibilityStatus()
    }

    // MARK: - Notification Permissions

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

    // MARK: - Post Notification

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

    // MARK: - Graceful Termination

    /// Stop volume and brightness monitoring and quit the app
    private func gracefulTerminate() {
        logger.debug("Stopping monitoring and quitting.")
        volumeMonitor?.stopMonitoring()

        if isBrightnessEnabled { brightnessMonitor?.stopMonitoring() }
        mediaKeyInterceptor?.stop()
        hudController?.stopDisplayChangeMonitoring()

        // Terminate without activating the app
        NSApp.terminate(nil)
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
