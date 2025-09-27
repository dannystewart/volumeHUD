import AppKit
import PolyLog
import SwiftUI
@preconcurrency import UserNotifications

private let kToggleNotificationName = Notification.Name("com.dannystewart.volumehud.toggle")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var volumeMonitor: VolumeMonitor!
    var hudController: HUDController!

    let logger = PolyLog()

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

        // Initialize the volume monitor and HUD controller
        volumeMonitor = VolumeMonitor()
        hudController = HUDController()
        hudController.volumeMonitor = volumeMonitor
        volumeMonitor.hudController = hudController

        // Request notification permission and post "started" notification (only on first run)
        requestNotificationAuthorizationIfNeeded { [weak self] granted in
            guard let self else { return }
            if granted {
                // Only show startup notification on first run
                if !UserDefaults.standard.bool(forKey: "hasShownStartupNotification") {
                    Task { @MainActor in
                        self.postUserNotification(
                            title: "volumeHUD started! (launch again to quit)", body: nil)
                        UserDefaults.standard.set(true, forKey: "hasShownStartupNotification")
                    }
                }
            }
        }

        // Start monitoring volume changes
        volumeMonitor.startMonitoring()

        // Start monitoring display configuration changes
        hudController.startDisplayChangeMonitoring()

        logger.info("Started monitoring volume changes from AppDelegate.")
    }

    // Handle attempts to launch the app a second time
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        // Treat reopening as a toggle request without activating the app
        scheduleQuit()
        return false
    }

    // If we get a new "open" event, also treat that as a toggle without activation
    func application(_ application: NSApplication, open urls: [URL]) {
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
        logger.info("Stopping monitoring and quitting.")
        volumeMonitor?.stopMonitoring()
        hudController?.stopDisplayChangeMonitoring()
        postUserNotification(title: "volumeHUD quit successfully!", body: nil)

        // Terminate without activating the app
        NSApp.terminate(nil)
    }

    // MARK: User Notifications

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
