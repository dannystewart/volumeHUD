//
//  HUDController.swift
//  Volume HUD
//
//  Created by Danny Stewart on 9/21/25.
//

import SwiftUI
import AppKit
import Combine

class HUDController: ObservableObject {
    @Published var isShowing = false
    
    private var hudWindow: NSWindow?
    private var hideTimer: Timer?
    weak var volumeMonitor: VolumeMonitor?
    
    func showVolumeHUD(volume: Float, isMuted: Bool) {
        DispatchQueue.main.async {
            self.displayHUD(volume: volume, isMuted: isMuted)
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
            let hostingView = NSHostingView(rootView: VolumeHUDView(volume: volume, isMuted: isMuted, isVisible: true))
            hostingView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 200, height: 200)
            
            window.contentView = hostingView
            window.orderFront(nil)
            
            isShowing = true
        }
        
        // Set timer to hide the HUD after 2 seconds
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            self.hideHUD()
        }
    }
    
    private func createHUDWindow() {
        let windowSize = NSSize(width: 200, height: 200)
        
        // Get the main screen
        guard let screen = NSScreen.main else { return }
        
        // Position the window lower on screen (about 1/5 from bottom)
        let screenFrame = screen.frame
        let windowRect = NSRect(
            x: (screenFrame.width - windowSize.width) / 2,
            y: screenFrame.height * 0.2,  // Position at 20% from bottom (lower than before)
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
        hudWindow?.orderOut(nil)
    }
}
