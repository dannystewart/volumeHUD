//
//  VolumeHUDApp.swift
//  volumeHUD
//
//  Created by Danny Stewart on 9/21/25.
//

import AppKit
import SwiftUI
@preconcurrency import UserNotifications

private let kToggleNotificationName = Notification.Name("com.dannystewart.volumehud.toggle")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var volumeMonitor: VolumeMonitor!
    var hudController: HUDController!

    // Prevent multiple rapid quit attempts
    private var isQuitting = false
    // Delay to allow reopen/open/notification routing to settle
    private let quitDelay: TimeInterval = 0.3

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep app running even when main window is closed
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the app headless and out of the Dock
        NSApplication.shared.setActivationPolicy(.accessory)

        // Listen for external toggle requests (optional: allows CLI/Automator to toggle)
        DistributedNotificationCenter.default()
            .addObserver(
                self,
                selector: #selector(handleToggleNotification),
                name: kToggleNotificationName,
                object: nil)

        // Initialize
        volumeMonitor = VolumeMonitor()
        hudController = HUDController()
        hudController.volumeMonitor = volumeMonitor
        volumeMonitor.hudController = hudController

        // Notifications: request permission and post "started"
        requestNotificationAuthorizationIfNeeded { [weak self] granted in
            guard let self else { return }
            if granted {
                // Ensure AppKit usage on main actor
                Task { @MainActor in
                    self.postUserNotification(title: "volumeHUD started", body: nil)
                }
            }
        }

        // Start monitoring volume changes
        volumeMonitor.startMonitoring()
        print("Started monitoring volume changes from AppDelegate")
    }

    // Handle attempts to "reopen" the app (e.g., user launches the app again)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        // Treat reopen as a toggle request without activating the app or showing the Dock icon
        scheduleQuit()
        return false
    }

    // If the system routes a new "open" event to the running app (e.g., via LaunchServices),
    // also treat that as a toggle without activation.
    func application(_ application: NSApplication, open urls: [URL]) {
        scheduleQuit()
    }

    @objc
    private func handleToggleNotification() {
        // Received an external toggle; schedule quit with the same delay
        scheduleQuit()
    }

    private func scheduleQuit() {
        // Ensure we remain accessory and do not activate
        NSApplication.shared.setActivationPolicy(.accessory)

        guard !isQuitting else { return }
        isQuitting = true

        // Give the run loop a moment to process any pending reopen/open/notification work
        DispatchQueue.main.asyncAfter(deadline: .now() + quitDelay) { [weak self] in
            guard let self else { return }
            self.gracefulTerminate()
        }
    }

    private func gracefulTerminate() {
        print("Stopping monitoring and quitting.")
        volumeMonitor?.stopMonitoring()
        postUserNotification(title: "volumeHUD stopped", body: nil)

        // Terminate without activating the app
        NSApp.terminate(nil)
    }

    // MARK: - User notifications

    private func requestNotificationAuthorizationIfNeeded(
        completion: @escaping @Sendable (Bool) -> Void
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
        if let body = body { content.body = body }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
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
