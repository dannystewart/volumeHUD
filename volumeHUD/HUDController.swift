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
    let logger = PolyLog.getLogger("HUDController", level: .debug)

    @MainActor
    func showVolumeHUD(volume: Float, isMuted: Bool) {
        self.displayHUD(volume: volume, isMuted: isMuted)
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
        let windowSize = NSSize(width: 210, height: 210)

        // Get the main screen
        guard let screen = NSScreen.main else { return }

        // Position the window lower on screen
        let screenFrame = screen.frame
        let windowRect = NSRect(
            x: (screenFrame.width - windowSize.width) / 2,
            y: screenFrame.height * 0.17,  // Distance from bottom of screen
            width: windowSize.width,
            height: windowSize.height
        )

        // Create the window with special properties for overlay
        hudWindow = NSWindow(
            contentRect: windowRect,
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

        // Start the window hidden (only show when volume changes)
        window.orderOut(nil)

        logger.debug("Created HUD window at: \(windowRect)")
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
    }
}
