//
//  HUDController.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
class HUDController: ObservableObject {
    @Published var isShowing = false

    let logger: Logger = .init()

    private var hudWindow: NSWindow?
    private var hostingView: NSHostingView<HUDPresentationView>?
    private let presentation: HUDPresentation = .init()
    private let animationDriver: HUDAnimationDriver = .init()
    private var lastShownStyle: HUDStyle?
    private var presentationGeneration = 0
    private var isHiding = false
    private var hideTimer: Timer?
    private var lastShownVolume: Float?
    private var lastShownMuted: Bool?
    private var lastShownBrightness: Float?
    private var lastShownHUDType: HUDType?
    private var isObservingDisplayChanges = false
    private let isPreviewMode: Bool

    init(isPreviewMode: Bool = false) {
        self.isPreviewMode = isPreviewMode
    }

    deinit {}

    func refreshStyle() {
        guard isShowing, let hudType = lastShownHUDType else { return }
        switch hudType {
        case .volume:
            displayHUD(hudType: hudType, value: lastShownVolume ?? 0, isMuted: lastShownMuted ?? false)
        case .brightness:
            displayHUD(hudType: hudType, value: lastShownBrightness ?? 0, isMuted: false)
        }
    }

    @MainActor
    func showVolumeHUD(volume: Float, isMuted: Bool) {
        displayHUD(hudType: .volume, value: volume, isMuted: isMuted)
    }

    #if !SANDBOX
        @MainActor
        func showBrightnessHUD(brightness: Float) {
            // Only show brightness HUD if the feature is enabled
            guard UserDefaults.standard.bool(forKey: "brightnessEnabled") else {
                logger.debug("Brightness HUD disabled; skipping display.")
                return
            }
            displayHUD(hudType: .brightness, value: brightness, isMuted: false)
        }
    #endif // !SANDBOX

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
            updateWindowPosition(for: lastShownHUDType)
            // Re-apply after a short delay to handle transient frame/layout updates macOS screen
            // geometry may still be adjusting after didChangeScreenParameters fires
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.updateWindowPosition(for: self?.lastShownHUDType)
            }
        }
    }

    @MainActor
    private func updateWindowPosition(for hudType: HUDType? = nil) {
        guard let window = hudWindow else { return }

        let style = HUDStyle.current
        let windowSize = NSSize(width: style.windowSize, height: style.windowSize)

        // Brightness HUD always shows on built-in display (since that's what it controls). Volume
        // HUD respects user preference for display location.
        let targetScreen: NSScreen
        let selectionReason: String
        #if !SANDBOX
            if hudType == .brightness {
                if let builtin = getBuiltinScreen() {
                    targetScreen = builtin
                    selectionReason = "brightness builtin"
                } else if let main = NSScreen.main {
                    targetScreen = main
                    selectionReason = "brightness builtin-missing fallback NSScreen.main"
                } else {
                    targetScreen = NSScreen.screens.first!
                    selectionReason = "brightness builtin-missing fallback firstScreen"
                }
            } else {
                // Check user preference for volume HUD location
                let followMouse = UserDefaults.standard.bool(forKey: "volumeHUDFollowsMouse")
                if followMouse {
                    if let mouse = getScreenWithMouse() {
                        targetScreen = mouse
                        selectionReason = "volume followsMouse"
                    } else if let main = NSScreen.main {
                        targetScreen = main
                        selectionReason = "volume followsMouse missing-mouse fallback NSScreen.main"
                    } else {
                        targetScreen = NSScreen.screens.first!
                        selectionReason = "volume followsMouse missing-mouse fallback firstScreen"
                    }
                } else {
                    if let primary = getPrimaryScreen() {
                        targetScreen = primary
                        selectionReason = "volume primaryDisplay"
                    } else if let main = NSScreen.main {
                        targetScreen = main
                        selectionReason = "volume primaryDisplay missing-primary fallback NSScreen.main"
                    } else {
                        targetScreen = NSScreen.screens.first!
                        selectionReason = "volume primaryDisplay missing-primary fallback firstScreen"
                    }
                }
            }
        #else
            // Check user preference for volume HUD location
            let followMouse = UserDefaults.standard.bool(forKey: "volumeHUDFollowsMouse")
            if followMouse {
                if let mouse = getScreenWithMouse() {
                    targetScreen = mouse
                    selectionReason = "volume followsMouse"
                } else if let main = NSScreen.main {
                    targetScreen = main
                    selectionReason = "volume followsMouse missing-mouse fallback NSScreen.main"
                } else {
                    targetScreen = NSScreen.screens.first!
                    selectionReason = "volume followsMouse missing-mouse fallback firstScreen"
                }
            } else {
                if let primary = getPrimaryScreen() {
                    targetScreen = primary
                    selectionReason = "volume primaryDisplay"
                } else if let main = NSScreen.main {
                    targetScreen = main
                    selectionReason = "volume primaryDisplay missing-primary fallback NSScreen.main"
                } else {
                    targetScreen = NSScreen.screens.first!
                    selectionReason = "volume primaryDisplay missing-primary fallback firstScreen"
                }
            }
        #endif // !SANDBOX

        let selectedDisplayID: CGDirectDisplayID? = {
            guard
                let screenNumber = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDirectDisplayID(screenNumber.uint32Value)
        }()
        let selectedDisplayIDText = selectedDisplayID.map { String($0) } ?? "unknown"
        logger.debug("HUD screen selection: \(selectionReason), displayID=\(selectedDisplayIDText), frame=\(targetScreen.frame)")

        // Use full screen frame to ignore Dock positioning
        let screenFrame = targetScreen.frame

        // Keep the visible HUD 140 points from the bottom, excluding any window padding.
        let newWindowRect = NSRect(
            x: screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2,
            y: screenFrame.origin.y + 140 - style.windowPadding,
            width: windowSize.width,
            height: windowSize.height,
        )

        // Update the window frame
        window.setFrame(newWindowRect, display: true)

        logger.debug("Updated HUD window position to: \(newWindowRect)")
    }

    /// Returns the NSScreen that currently contains the mouse cursor
    private func getScreenWithMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
            return screen
        }

        return nil
    }

    /// Returns the NSScreen corresponding to the built-in display, if present
    private func getBuiltinScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                let displayID = CGDirectDisplayID(screenNumber.uint32Value)
                if CGDisplayIsBuiltin(displayID) != 0 {
                    return screen
                }
            }
        }
        return nil
    }

    /// Returns the NSScreen corresponding to macOS's primary (menu bar) display, if present.
    private func getPrimaryScreen() -> NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                let displayID = CGDirectDisplayID(screenNumber.uint32Value)
                if displayID == mainDisplayID {
                    return screen
                }
            }
        }
        return nil
    }

    @MainActor
    private func displayHUD(hudType: HUDType, value: Float, isMuted: Bool) {
        // Cancel any existing hide timer
        hideTimer?.invalidate()
        presentationGeneration += 1
        let generation = presentationGeneration
        let style = HUDStyle.current

        // Modern needs a different native window class; never change Classic's window appearance to
        // accommodate glass.
        if hudWindow == nil || (lastShownStyle != nil && lastShownStyle != style) {
            animationDriver.cancel()
            hudWindow?.orderOut(nil)
            hostingView = nil
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
            if
                window.isVisible,
                !isHiding,
                !shouldUpdateContent,
                lastShownStyle == style,
                style != .modern || presentation.isPresented
            {
                scheduleHideTimer()
                return
            }

            let needsEntrance = !window.isVisible || lastShownStyle != style
            let wasHiding = isHiding
            isHiding = false
            // Cancel an interrupted fade before presenting new content.
            if style == .classic {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    window.animator().alphaValue = 1
                }
            }
            if needsEntrance {
                presentation.isPresented = false
                presentation.scale = ModernHUDMetrics.entranceScale
                presentation.blurRadius = ModernHUDMetrics.transitionBlurRadius
            }

            let content = HUDPresentationView(
                hudType: hudType,
                value: value,
                isMuted: isMuted,
                style: style,
                presentation: presentation,
            )
            // Keep Modern's glass container alive across repeated keypresses. Classic retains its
            // original fresh-hosting-view behavior.
            let newHostingView: NSHostingView<HUDPresentationView>
            if style == .modern, lastShownStyle == .modern, let hostingView {
                newHostingView = hostingView
                newHostingView.rootView = content
            } else {
                newHostingView = NSHostingView(rootView: content)
            }
            newHostingView.frame = NSRect(x: 0, y: 0, width: style.windowSize, height: style.windowSize)

            // Preserve Classic's backing configuration; let SwiftUI own Modern's glass rendering
            // layers without imposing a custom backing layer.
            if style == .classic {
                newHostingView.wantsLayer = true
                newHostingView.layer?.backgroundColor = NSColor.clear.cgColor
            }

            if window.contentView !== newHostingView {
                if let oldView = window.contentView { oldView.removeFromSuperview() }
                window.contentView = newHostingView
            }
            hostingView = newHostingView

            // Update position based on HUD type
            updateWindowPosition(for: hudType)

            // Show the window
            if style == .modern, needsEntrance {
                window.alphaValue = 0
            }
            window.orderFront(nil)
            isShowing = true
            lastShownStyle = style

            if style == .modern, needsEntrance || wasHiding || !presentation.isPresented {
                newHostingView.layoutSubtreeIfNeeded()
                DispatchQueue.main.async { [weak self] in
                    guard let self, presentationGeneration == generation else { return }
                    animateModernHUD(showing: true, generation: generation)
                }
            }
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
        let generation = presentationGeneration
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, presentationGeneration == generation else { return }
                hideHUD()
            }
        }
    }

    @MainActor
    private func createHUDWindow() {
        // Create the window with special properties for overlay
        let contentRect = NSRect(x: 0, y: 0, width: 200, height: 200)
        if HUDStyle.current == .modern {
            let panel = ModernHUDPanel(
                contentRect: contentRect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
            )
            panel.hidesOnDeactivate = false
            hudWindow = panel
        } else {
            hudWindow = NSWindow(
                contentRect: contentRect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
            )
        }

        guard let window = hudWindow else {
            logger.error("createHUDWindow: failed to create NSWindow (hudWindow is nil)")
            return
        }

        // Configure window properties for overlay behavior. Use `.statusBar` level to appear above
        // normal windows but not block Exposé/Show Desktop.
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Avoid .stationary: it can interact badly with Mission Control / Show Desktop.
        // `canJoinAllSpaces` is sufficient for cross-space visibility.
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .transient]

        // Set the initial position
        updateWindowPosition()

        // Start the window hidden (only show when volume changes)
        window.orderOut(nil)

        logger.debug("Created HUD window.")
    }

    // MARK: Hide HUD

    @MainActor
    private func hideHUD() {
        guard let window = hudWindow, window.isVisible, !isHiding else { return }
        isHiding = true
        presentationGeneration += 1
        let generation = presentationGeneration

        if lastShownStyle == .modern {
            animateModernHUD(showing: false, generation: generation)
            return
        }

        // Animate fade-out before hiding
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, presentationGeneration == generation else { return }
                window.orderOut(nil)
                window.alphaValue = 1.0 // Reset for next show
                isShowing = false
                isHiding = false
            }
        }
    }

    private func animateModernHUD(showing: Bool, generation: Int) {
        guard let window = hudWindow, let screen = window.screen ?? NSScreen.screens.first else { return }
        let startOpacity = window.alphaValue
        let startScale = presentation.scale
        let startBlur = presentation.blurRadius
        let endOpacity: CGFloat = showing ? 1 : 0
        let endScale: CGFloat = showing ? 1 : ModernHUDMetrics.exitScale
        let endBlur: CGFloat = showing ? 0 : ModernHUDMetrics.transitionBlurRadius
        presentation.isPresented = showing

        animationDriver.animate(
            on: screen,
            duration: showing ? ModernHUDMetrics.entranceDuration : ModernHUDMetrics.exitDuration,
            curve: showing ? .easeOut : .easeIn,
            update: { [weak self, weak window] progress in
                guard let self, let window else { return }
                let fraction = CGFloat(progress)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    presentation.scale = startScale + (endScale - startScale) * fraction
                    presentation.blurRadius = startBlur + (endBlur - startBlur) * fraction
                }
                // Commit the foreground and material geometry for this same tick,
                // then set native opacity directly: no second animation engine.
                hostingView?.layoutSubtreeIfNeeded()
                window.alphaValue = startOpacity + (endOpacity - startOpacity) * fraction
            },
            completion: { [weak self, weak window] in
                guard let self, let window, !showing, presentationGeneration == generation else { return }
                window.orderOut(nil)
                window.alphaValue = 1
                isShowing = false
                isHiding = false
            },
        )
    }
}
