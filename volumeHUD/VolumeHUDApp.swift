import AppKit
import Polykit
import SwiftUI
@preconcurrency import UserNotifications

private let kToggleNotificationName = Notification.Name("com.dannystewart.volumehud.toggle")

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var volumeMonitor: VolumeMonitor!
    var hudController: HUDController!
    var aboutWindow: NSWindow?

    let logger = PolyLog()

    // Prevent multiple rapid quit attempts
    private var isQuitting = false
    // Delay to allow reopen/open/notification routing to settle
    private let quitDelay: TimeInterval = 0.3

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
                            title: "volumeHUD started! (launch again for options)", body: nil
                        )
                        UserDefaults.standard.set(true, forKey: "hasShownStartupNotification")
                    }
                }
            }
        }

        // Start monitoring volume changes
        volumeMonitor.startMonitoring()

        // Start monitoring display configuration changes
        hudController.startDisplayChangeMonitoring()
    }

    // Handle attempts to launch the app a second time
    func applicationShouldHandleReopen(
        _: NSApplication, hasVisibleWindows _: Bool
    ) -> Bool {
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
            defer: false
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
        window.level = .floating

        aboutWindow = window

        // Temporarily switch to regular app to show window properly
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func gracefulTerminate() {
        logger.info("Stopping monitoring and quitting.")
        volumeMonitor?.stopMonitoring()
        hudController?.stopDisplayChangeMonitoring()
        postUserNotification(title: "volumeHUD quit successfully!", body: nil)

        // Terminate without activating the app
        NSApp.terminate(nil)
    }

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
            trigger: nil
        )
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
