//
//  HUDController.swift
//  Volume HUD
//
//  Created by Danny Stewart on 9/21/25.
//

import AppKit
import Combine
import SwiftUI

class HUDController: ObservableObject {
    @Published var isShowing = false

    private var hudWindow: NSWindow?
    private var hostingView: NSHostingView<VolumeHUDView>?
    private var hideTimer: Timer?
    weak var volumeMonitor: VolumeMonitor?

    func showVolumeHUD(volume: Float, isMuted: Bool) {
        if Thread.isMainThread {
            self.displayHUD(volume: volume, isMuted: isMuted)
        } else {
            DispatchQueue.main.async {
                self.displayHUD(volume: volume, isMuted: isMuted)
            }
        }
    }

    private func displayHUD(volume: Float, isMuted: Bool) {
        // Cancel any existing hide timer
        hideTimer?.invalidate()

        // Create or update the HUD window
        if hudWindow == nil {
            createHUDWindow()
        }

        // Update the content view
        if let window = hudWindow {
            if hostingView == nil {
                hostingView = NSHostingView(
                    rootView: VolumeHUDView(volume: volume, isMuted: isMuted, isVisible: true)
                )
                hostingView?.frame =
                    window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 200, height: 200)
                window.contentView = hostingView
            } else {
                hostingView?.rootView = VolumeHUDView(
                    volume: volume,
                    isMuted: isMuted,
                    isVisible: true
                )
            }

            window.orderFront(nil)
            isShowing = true
        }

        // Set timer to hide the HUD
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            self.hideHUD()
        }
    }

    private func createHUDWindow() {
        let windowSize = NSSize(width: 200, height: 200)

        // Get the main screen
        guard let screen = NSScreen.main else { return }

        // Position the window lower on screen
        let screenFrame = screen.frame
        let windowRect = NSRect(
            x: (screenFrame.width - windowSize.width) / 2,
            y: screenFrame.height * 0.15,  // Distance from bottom of screen
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

        print("Created HUD window at: \(windowRect)")
    }

    private func hideHUD() {
        DispatchQueue.main.async {
            self.hudWindow?.orderOut(nil)
            self.isShowing = false
        }
    }

    deinit {
        hideTimer?.invalidate()
        hostingView = nil
        hudWindow?.orderOut(nil)
    }
}
