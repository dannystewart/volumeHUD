//
//  HUDController.swift
//  volumeHUD
//
//  Created by Danny Stewart on 9/21/25.
//

import AppKit
import Combine
import PolyLog
import SwiftUI

class HUDController: ObservableObject, @unchecked Sendable {
    @Published var isShowing = false

    private var hudWindow: NSWindow?
    private var hostingView: NSHostingView<VolumeHUDView>?
    private var hideTimer: Timer?
    weak var volumeMonitor: VolumeMonitor?
    private var lastShownVolume: Float?
    private var lastShownMuted: Bool?
    private var isObservingDisplayChanges = false
    private var displayChangeObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var positionCheckTimer: Timer?

    let logger = PolyLog()

    @MainActor
    func showVolumeHUD(volume: Float, isMuted: Bool) {
        self.displayHUD(volume: volume, isMuted: isMuted)
    }

    @MainActor
    func forceUpdatePosition() {
        logger.debug("Manually forcing position update.")
        updateWindowPosition()
    }

    @MainActor
    func startDisplayChangeMonitoring() {
        // Monitor for display configuration changes using NSApplication notification
        displayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplayConfigurationChange()
        }

        // Also monitor for workspace screen changes
        workspaceObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDisplayConfigurationChange()
        }

        // Add a periodic check as a fallback
        positionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.checkAndUpdatePosition()
            }
        }

        logger.debug("Started monitoring display configuration changes.")
    }

    @MainActor
    private func checkAndUpdatePosition() {
        guard let window = hudWindow else { return }

        // Get current screen info
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // Check if the window is positioned correctly relative to the current screen
        let expectedX = (screenFrame.width - 210) / 2
        let expectedY = screenFrame.height * 0.17
        let currentFrame = window.frame

        // If the position is significantly off, update it
        if abs(currentFrame.origin.x - expectedX) > 50
            || abs(currentFrame.origin.y - expectedY) > 50
        {
            logger.debug("Position check detected misalignment, updating position.")
            updateWindowPosition()
        }
    }

    @MainActor
    func stopDisplayChangeMonitoring() {
        if let observer = displayChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            displayChangeObserver = nil
        }

        if let observer = workspaceObserver {
            NotificationCenter.default.removeObserver(observer)
            workspaceObserver = nil
        }

        positionCheckTimer?.invalidate()
        positionCheckTimer = nil

        logger.debug("Stopped monitoring display configuration changes.")
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
        guard let window = hudWindow else {
            logger.debug("No HUD window to update position for.")
            return
        }

        let windowSize = NSSize(width: 210, height: 210)

        // Get the current main screen
        guard let screen = NSScreen.main else {
            logger.debug("No main screen available.")
            return
        }

        // Calculate new position
        let screenFrame = screen.frame
        let newWindowRect = NSRect(
            x: (screenFrame.width - windowSize.width) / 2,
            y: screenFrame.height * 0.17,  // Distance from bottom of screen
            width: windowSize.width,
            height: windowSize.height
        )

        logger.debug("Screen frame: \(screenFrame)")
        logger.debug("Calculated new window rect: \(newWindowRect)")
        logger.debug("Current window frame: \(window.frame)")

        // Update the window frame
        window.setFrame(newWindowRect, display: true)

        logger.debug("Updated HUD window position to: \(newWindowRect)")
    }

    @MainActor
    private func displayHUD(volume: Float, isMuted: Bool) {
        // Cancel any existing hide timer
        hideTimer?.invalidate()

        // Create or update the HUD window
        if hudWindow == nil {
            createHUDWindow()
        }

        // Update the content view
        if let window = hudWindow {
            let shouldUpdateContent =
                hostingView == nil
                || lastShownVolume == nil
                || abs((lastShownVolume ?? -1) - volume) > 0.0005
                || (lastShownMuted ?? !isMuted) != isMuted

            // If nothing changed and the window is already visible, just extend the timer
            if window.isVisible && !shouldUpdateContent {
                scheduleHideTimer()
                return
            }

            if hostingView == nil {
                hostingView = NSHostingView(
                    rootView: VolumeHUDView(volume: volume, isMuted: isMuted, isVisible: true)
                )
                hostingView?.frame =
                    window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 210, height: 210)
                window.contentView = hostingView
            } else if shouldUpdateContent {
                hostingView?.rootView = VolumeHUDView(
                    volume: volume,
                    isMuted: isMuted,
                    isVisible: true
                )
            }

            window.orderFront(nil)
            isShowing = true
        }

        scheduleHideTimer()

        // Remember last shown state to avoid redundant view rebuilds
        lastShownVolume = volume
        lastShownMuted = isMuted
    }

    @MainActor
    private func scheduleHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { _ in
            DispatchQueue.main.async {
                self.hideHUD()
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
            defer: false
        )

        guard let window = hudWindow else { return }

        // Configure window properties for overlay behavior
        window.level = .statusBar + 1  // Above menu bar
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

    deinit {
        // Clean up resources synchronously in deinit
        // The window will be cleaned up when the app terminates
        hideTimer?.invalidate()
        hostingView = nil

        // Clean up display change monitoring
        if let observer = displayChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        if let observer = workspaceObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        positionCheckTimer?.invalidate()
    }
}
