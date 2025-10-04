import AppKit
import Combine
import Foundation
import PolyKit
import SwiftUI

@MainActor
class HUDController: ObservableObject {
    @Published var isShowing = false

    private var hudWindow: NSWindow?
    private var hostingView: NSHostingView<HUDView>?
    private var hideTimer: Timer?
    weak var volumeMonitor: VolumeMonitor?
    weak var brightnessMonitor: BrightnessMonitor?
    private var lastShownVolume: Float?
    private var lastShownMuted: Bool?
    private var lastShownBrightness: Float?
    private var lastShownHUDType: HUDType?
    private var isObservingDisplayChanges = false
    private let isPreviewMode: Bool
    let logger = PolyLog()

    init(isPreviewMode: Bool = false) {
        self.isPreviewMode = isPreviewMode
    }

    @MainActor
    func showVolumeHUD(volume: Float, isMuted: Bool) {
        displayHUD(hudType: .volume, value: volume, isMuted: isMuted)
    }

    @MainActor
    func showBrightnessHUD(brightness: Float) {
        // Only show brightness HUD if the feature is enabled
        guard UserDefaults.standard.bool(forKey: "brightnessEnabled") else {
            logger.debug("Brightness HUD disabled - skipping display")
            return
        }
        displayHUD(hudType: .brightness, value: brightness, isMuted: false)
    }

    @MainActor
    func startDisplayChangeMonitoring() {
        guard !isObservingDisplayChanges else { return }

        // Skip display monitoring in preview mode
        if isPreviewMode {
            logger.debug("Skipping display monitoring in preview mode.")
            isObservingDisplayChanges = true
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil,
        )
        isObservingDisplayChanges = true

        logger.debug("Started monitoring display configuration changes.")
    }

    @MainActor
    func stopDisplayChangeMonitoring() {
        guard isObservingDisplayChanges else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil,
        )
        isObservingDisplayChanges = false

        logger.debug("Stopped monitoring display configuration changes.")
    }

    @objc
    private func displayConfigurationDidChange(_: Notification) {
        // Ensure we hop to the main actor for UI work
        Task { @MainActor in
            self.handleDisplayConfigurationChange()
        }
    }

    @MainActor
    private func handleDisplayConfigurationChange() {
        logger.debug("Display configuration changed, updating HUD position.")

        // If the HUD window exists, update its position
        if hudWindow != nil {
            updateWindowPosition()
        }
    }

    @MainActor
    private func updateWindowPosition() {
        guard let window = hudWindow else { return }

        let windowSize = NSSize(width: 210, height: 210)

        // Get the current main screen
        guard let screen = NSScreen.main else { return }

        // Calculate new position
        let screenFrame = screen.frame
        let newWindowRect = NSRect(
            x: (screenFrame.width - windowSize.width) / 2,
            y: screenFrame.height * 0.17, // Distance from bottom of screen
            width: windowSize.width,
            height: windowSize.height,
        )

        // Update the window frame
        window.setFrame(newWindowRect, display: true)

        logger.debug("Updated HUD window position to: \(newWindowRect)")
    }

    @MainActor
    private func displayHUD(hudType: HUDType, value: Float, isMuted: Bool) {
        // Cancel any existing hide timer
        hideTimer?.invalidate()

        // Create or update the HUD window
        if hudWindow == nil {
            createHUDWindow()
        }

        // Update the content view
        if let window = hudWindow {
            let shouldUpdateContent: Bool =
                switch hudType {
                case .volume:
                    hostingView == nil
                        || lastShownHUDType != hudType
                        || lastShownVolume == nil
                        || abs((lastShownVolume ?? -1) - value) > 0.0005
                        || (lastShownMuted ?? !isMuted) != isMuted
                case .brightness:
                    hostingView == nil
                        || lastShownHUDType != hudType
                        || lastShownBrightness == nil
                        || abs((lastShownBrightness ?? -1) - value) > 0.0005
                }

            // If nothing changed and the window is already visible, just extend the timer
            if window.isVisible, !shouldUpdateContent {
                scheduleHideTimer()
                return
            }

            // Always recreate hosting view to avoid SwiftUI state issues
            let newHostingView = NSHostingView(rootView: HUDView(hudType: hudType, value: value, isMuted: isMuted, isVisible: true))
            newHostingView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 210, height: 210)

            // Ensure hosting view background is clear for proper material rendering
            newHostingView.wantsLayer = true
            newHostingView.layer?.backgroundColor = NSColor.clear.cgColor

            // Remove old content view if it exists
            if let oldView = window.contentView { oldView.removeFromSuperview() }

            window.contentView = newHostingView
            hostingView = newHostingView

            // Show the window
            window.orderFront(nil)
            isShowing = true
        }

        scheduleHideTimer()

        // Remember last shown state to avoid redundant view rebuilds
        lastShownHUDType = hudType
        switch hudType {
        case .volume:
            lastShownVolume = value
            lastShownMuted = isMuted
        case .brightness:
            lastShownBrightness = value
        }
    }

    @MainActor
    private func scheduleHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideHUD()
            }
        }
    }

    @MainActor
    private func createHUDWindow() {
        // Create the window with special properties for overlay
        hudWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 210),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
        )

        guard let window = hudWindow else {
            logger.error("createHUDWindow: failed to create NSWindow (hudWindow is nil)")
            return
        }

        // Configure window properties for overlay behavior
        window.level = .statusBar + 1 // Above menu bar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Make sure window appears on all spaces and can't be activated
        window.canHide = false

        // Set the initial position
        updateWindowPosition()

        // Start the window hidden (only show when volume changes)
        window.orderOut(nil)

        logger.debug("Created HUD window.")
    }

    @MainActor
    private func hideHUD() {
        hudWindow?.orderOut(nil)
        isShowing = false
    }

    deinit {}
}
