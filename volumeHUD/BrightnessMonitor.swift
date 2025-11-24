//
//  BrightnessMonitor.swift
//  by Danny Stewart (2025)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import AppKit
import Combine
import CoreGraphics
import Foundation
import IOKit
import IOKit.pwr_mgt
import PolyKit

class BrightnessMonitor: ObservableObject, @unchecked Sendable {
    @Published var currentBrightness: Float = 0.0

    weak var hudController: HUDController?

    let logger: PolyLog = .init()

    private var accessibilityEnabled: Bool
    private var isMonitoring = false
    private var previousBrightness: Float = 0.0
    private var brightnessPollingTimer: Timer?
    private var systemEventMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var hidEventTap: CFMachPort?
    private var hidEventTapRunLoopSource: CFRunLoopSource?
    private var lastBrightnessKeyTime: TimeInterval = 0
    private var lastHandledKeyCode: Int = 0
    private var lastKeyHandleTime: TimeInterval = 0
    private var hasLoggedBrightnessError = false
    private var hasLoggedNoDisplayDetected = false
    private var brightnessAvailable = false
    private let isPreviewMode: Bool
    private var isObservingDisplayChanges = false
    private var restartTask: Task<Void, Never>?

    /// Cache DisplayServices function pointers
    private var displayServicesHandle: UnsafeMutableRawPointer?
    private var canChangeBrightnessFunc: (@convention(c) (CGDirectDisplayID) -> Bool)?
    private var getBrightnessFunc: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> kern_return_t)?

    init(isPreviewMode: Bool = false) {
        self.isPreviewMode = isPreviewMode

        // Initialize with a timestamp far in the past so initial startup doesn't show HUD
        lastBrightnessKeyTime = 0

        // Skip expensive operations in preview mode
        if isPreviewMode {
            accessibilityEnabled = false
            currentBrightness = 0.75
            brightnessAvailable = true
        } else {
            // Initialize accessibility status
            accessibilityEnabled = AXIsProcessTrusted()

            // Load DisplayServices framework once at initialization
            loadDisplayServices()
        }
    }

    deinit {}

    /// Update the accessibility status after permissions may have changed
    func updateAccessibilityStatus() {
        let newAccessibilityEnabled = AXIsProcessTrusted()

        if newAccessibilityEnabled != accessibilityEnabled {
            logger.info("Brightness monitor accessibility status changed: \(accessibilityEnabled) -> \(newAccessibilityEnabled)")
            accessibilityEnabled = newAccessibilityEnabled
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Skip all monitoring in preview mode
        if isPreviewMode {
            logger.debug("Skipping brightness monitoring in preview mode.")
            isMonitoring = true
            return
        }

        logger.debug("BrightnessMonitor.startMonitoring() called")
        logger.debug("DisplayServices handle: \(displayServicesHandle != nil)")
        logger.debug("canChangeBrightnessFunc: \(canChangeBrightnessFunc != nil)")
        logger.debug("getBrightnessFunc: \(getBrightnessFunc != nil)")

        // Get initial brightness without showing HUD
        updateBrightnessOnStartup()

        // Start polling for brightness changes
        startBrightnessPolling()

        // Start monitoring system-defined events for brightness key presses
        startSystemEventMonitoring()
        startEventTap()

        // Monitor display configuration changes to restart event monitoring when needed
        startDisplayChangeMonitoring()

        isMonitoring = true
        logger.debug("Started monitoring for brightness changes.")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        // Stop polling
        stopBrightnessPolling()

        // Stop system event monitoring
        stopSystemEventMonitoring()
        stopEventTap()

        // Stop display change monitoring
        stopDisplayChangeMonitoring()

        // Cancel any pending restart task
        restartTask?.cancel()
        restartTask = nil

        isMonitoring = false
        logger.debug("Stopped monitoring for brightness changes.")
    }

    /// Check if a brightness delta matches user-initiated key press patterns
    /// User key presses always change brightness by multiples of 1/16th (0.0625)
    private func isUserInitiatedBrightnessChange(_ delta: Float, rawBrightness: Float) -> Bool {
        let baseStepSize: Float = 0.0625
        let tolerance: Float = 0.0001
        let absDelta = abs(delta)

        for multiplier in 1 ... 4 {
            let expectedDelta = baseStepSize * Float(multiplier)
            if abs(absDelta - expectedDelta) < tolerance {
                let rawStepPosition = rawBrightness * 16.0
                let nearestStep = round(rawStepPosition)
                let rawStepError = abs(rawStepPosition - nearestStep)

                if rawStepError < 0.01 {
                    return true
                }
            }
        }

        return false
    }

    private func loadDisplayServices() {
        logger.debug("Attempting to load DisplayServices framework...")

        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            if let error = dlerror() {
                logger.error("Could not load DisplayServices framework: \(String(cString: error))")
            } else {
                logger.error("Could not load DisplayServices framework (unknown error).")
            }
            return
        }

        logger.debug("DisplayServices framework handle obtained, looking for functions...")

        guard
            let canChangeBrightnessPtr = dlsym(handle, "DisplayServicesCanChangeBrightness"),
            let getBrightnessPtr = dlsym(handle, "DisplayServicesGetBrightness") else
        {
            dlclose(handle)
            if let error = dlerror() {
                logger.error("Could not find DisplayServices brightness functions: \(String(cString: error))")
            } else {
                logger.error("Could not find DisplayServices brightness functions (unknown error).")
            }
            return
        }

        displayServicesHandle = handle
        canChangeBrightnessFunc = unsafeBitCast(canChangeBrightnessPtr, to: (@convention(c) (CGDirectDisplayID) -> Bool).self)
        getBrightnessFunc = unsafeBitCast(getBrightnessPtr, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> kern_return_t).self)

        logger.info("DisplayServices framework loaded successfully!")
    }

    /// Returns the CGDirectDisplayID for the built-in display, if present
    private func getBuiltinDisplayID() -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        if result != .success || displayCount == 0 {
            return nil
        }

        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        result = CGGetActiveDisplayList(displayCount, &activeDisplays, &displayCount)
        if result != .success {
            return nil
        }

        for display in activeDisplays.prefix(Int(displayCount)) {
            if CGDisplayIsBuiltin(display) != 0 {
                return display
            }
        }

        return nil
    }

    private func updateBrightnessOnStartup() {
        if let brightness = getCurrentBrightness() {
            // Quantize brightness to 16 steps to match the brightness bars
            let quantizedBrightness = round(brightness * 16.0) / 16.0
            currentBrightness = quantizedBrightness
            previousBrightness = quantizedBrightness
            brightnessAvailable = true
            logger.debug("Initial brightness set: \(Int(quantizedBrightness * 100))%")
        } else {
            brightnessAvailable = false
            if !hasLoggedBrightnessError {
                logger.warning("Brightness control not available; this may be an external display or a system without brightness control.")
                hasLoggedBrightnessError = true
            }
        }
    }

    private func getCurrentBrightness() -> Float? {
        // Use cached DisplayServices function pointers
        guard
            let canChangeBrightness = canChangeBrightnessFunc,
            let getBrightness = getBrightnessFunc else
        {
            logger.error("getCurrentBrightness: Function pointers not available.")
            return nil
        }

        // Always target the built-in display rather than the current main display
        guard let builtinDisplay = getBuiltinDisplayID() else {
            if !hasLoggedNoDisplayDetected {
                logger.warning("getCurrentBrightness: No built-in display detected.")
                hasLoggedNoDisplayDetected = true
            }
            return nil
        }

        let canChange = canChangeBrightness(builtinDisplay)
        guard canChange else {
            logger.warning("getCurrentBrightness: Built-in display cannot change brightness (id: \(builtinDisplay))")
            return nil
        }

        var brightness: Float = 0.0
        let result = getBrightness(builtinDisplay, &brightness)
        if result == KERN_SUCCESS {
            return brightness
        }

        logger.error("getCurrentBrightness: getBrightness failed with result \(result)")
        return nil
    }

    private func startBrightnessPolling() {
        // Poll more frequently than volume since brightness changes are more granular
        brightnessPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForBrightnessChange()
            }
        }
        logger.debug("Started polling for brightness changes.")
    }

    private func stopBrightnessPolling() {
        brightnessPollingTimer?.invalidate()
        brightnessPollingTimer = nil
        logger.debug("Stopped brightness polling.")
    }

    private func startSystemEventMonitoring() {
        // Monitor system-defined events for brightness key presses (F1/F2)
        systemEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let self else { return }

            let subtype = Int(event.subtype.rawValue)
            let data1 = Int(event.data1)
            let keyCode = (data1 & 0xFFFF_0000) >> 16
            let keyFlags = data1 & 0x0000_FFFF
            let keyState = (keyFlags & 0xFF00) >> 8
            let isKeyDown = keyState == 0x0A

            Task { @MainActor [weak self] in
                guard let self else { return }
                handleSystemDefinedEventData(subtype: subtype, keyCode: keyCode, isKeyDown: isKeyDown)
            }
        }

        logger.debug("Started monitoring system-defined events for brightness keys (NSEvent).")
    }

    private func stopSystemEventMonitoring() {
        if let monitor = systemEventMonitor {
            NSEvent.removeMonitor(monitor)
            systemEventMonitor = nil
        }
    }

    private func startEventTap() {
        // Install a CGEvent tap to reliably observe NX_SYSDEFINED events without capturing context
        let systemDefinedMask: CGEventMask = 1 << 14 // kCGEventSystemDefined = 14
        // Both session and HID taps share the same userInfo pointer to self
        // This is safe because self outlives both taps (stopped in stopEventTap)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: systemDefinedMask,
                callback: { _, type, cgEvent, opaqueInfo -> Unmanaged<CGEvent>? in
                    // If the tap is disabled (timeout or user input), re-enable both taps
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let opaqueInfo {
                            let monitor = Unmanaged<BrightnessMonitor>.fromOpaque(opaqueInfo).takeUnretainedValue()
                            if let sessionTap = monitor.eventTap {
                                CGEvent.tapEnable(tap: sessionTap, enable: true)
                            }
                            if let hidTap = monitor.hidEventTap {
                                CGEvent.tapEnable(tap: hidTap, enable: true)
                            }
                        }
                        return Unmanaged.passUnretained(cgEvent)
                    }

                    // Only handle systemDefined events (kCGEventSystemDefined = 14)
                    guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: cgEvent) else {
                        return Unmanaged.passUnretained(cgEvent)
                    }
                    guard let opaqueInfo else {
                        return Unmanaged.passUnretained(cgEvent)
                    }
                    let monitor = Unmanaged<BrightnessMonitor>.fromOpaque(opaqueInfo).takeUnretainedValue()

                    let subtype = Int(nsEvent.subtype.rawValue)
                    let data1 = Int(nsEvent.data1)
                    let keyCode = (data1 & 0xFFFF_0000) >> 16
                    let keyFlags = data1 & 0x0000_FFFF
                    let keyState = (keyFlags & 0xFF00) >> 8
                    let isKeyDown = keyState == 0x0A

                    Task { @MainActor in
                        monitor.handleSystemDefinedEventData(subtype: subtype, keyCode: keyCode, isKeyDown: isKeyDown)
                    }

                    return Unmanaged.passUnretained(cgEvent)
                },
                userInfo: userInfo,
            ) else
        {
            logger.warning("Failed to create CGEvent tap for systemDefined events; falling back to NSEvent only.")
            return
        }

        eventTap = tap
        eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = eventTapRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            logger.debug("Started CGEvent tap (session-level) for systemDefined events.")
        } else {
            logger.warning("Failed to create run loop source for event tap.")
        }

        // Also install a HID-level tap as a backup; this may be more resilient to display configuration changes
        if
            let hidTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: systemDefinedMask,
                callback: { _, type, cgEvent, opaqueInfo -> Unmanaged<CGEvent>? in
                    // If the tap is disabled, re-enable both taps
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let opaqueInfo {
                            let monitor = Unmanaged<BrightnessMonitor>.fromOpaque(opaqueInfo).takeUnretainedValue()
                            if let sessionTap = monitor.eventTap {
                                CGEvent.tapEnable(tap: sessionTap, enable: true)
                            }
                            if let hidTap = monitor.hidEventTap {
                                CGEvent.tapEnable(tap: hidTap, enable: true)
                            }
                        }
                        return Unmanaged.passUnretained(cgEvent)
                    }

                    guard type.rawValue == 14, let nsEvent = NSEvent(cgEvent: cgEvent) else {
                        return Unmanaged.passUnretained(cgEvent)
                    }
                    guard let opaqueInfo else {
                        return Unmanaged.passUnretained(cgEvent)
                    }
                    let monitor = Unmanaged<BrightnessMonitor>.fromOpaque(opaqueInfo).takeUnretainedValue()

                    let subtype = Int(nsEvent.subtype.rawValue)
                    let data1 = Int(nsEvent.data1)
                    let keyCode = (data1 & 0xFFFF_0000) >> 16
                    let keyFlags = data1 & 0x0000_FFFF
                    let keyState = (keyFlags & 0xFF00) >> 8
                    let isKeyDown = keyState == 0x0A

                    Task { @MainActor in
                        monitor.handleSystemDefinedEventData(subtype: subtype, keyCode: keyCode, isKeyDown: isKeyDown)
                    }

                    return Unmanaged.passUnretained(cgEvent)
                },
                userInfo: userInfo,
            )
        {
            hidEventTap = hidTap
            hidEventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, hidTap, 0)
            if let hidSource = hidEventTapRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), hidSource, .commonModes)
                CGEvent.tapEnable(tap: hidTap, enable: true)
                logger.debug("Started CGEvent tap (HID-level) for systemDefined events.")
            } else {
                logger.warning("Failed to create run loop source for HID event tap.")
            }
        } else {
            logger.debug("HID-level event tap not available; relying on session-level tap only.")
        }
    }

    private func stopEventTap() {
        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTapRunLoopSource = nil
        eventTap = nil

        if let hidSource = hidEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), hidSource, .commonModes)
        }
        if let hidTap = hidEventTap {
            CGEvent.tapEnable(tap: hidTap, enable: false)
        }
        hidEventTapRunLoopSource = nil
        hidEventTap = nil
    }

    // MARK: - Display Change Monitoring

    private func startDisplayChangeMonitoring() {
        guard !isObservingDisplayChanges else { return }
        if isPreviewMode {
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
    }

    private func stopDisplayChangeMonitoring() {
        guard isObservingDisplayChanges else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil,
        )
        isObservingDisplayChanges = false
    }

    @objc
    private func displayConfigurationDidChange(_: Notification) {
        // Cancel any pending restart task to debounce rapid-fire display config changes
        restartTask?.cancel()

        // Debounce display configuration changes that fire in rapid succession
        // Lid close/open can trigger 3-4 notifications over ~1 second
        restartTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 500000000) // 500ms
                logger.info("Display configuration stabilized, restarting brightness event monitoring.")
                self.restartEventMonitoring()
            } catch {
                // Task was cancelled - a newer restart is pending
                logger.debug("Display configuration restart cancelled (newer pending).")
            }
        }
    }

    @MainActor
    private func restartEventMonitoring() {
        stopSystemEventMonitoring()
        stopEventTap()
        startSystemEventMonitoring()
        startEventTap()
        logger.debug("Event monitoring restarted.")
    }

    // MARK: - Brightness Change Detection

    @MainActor
    private func checkForBrightnessChange() {
        // Always probe brightness so we can recover after display config changes
        guard let brightness = getCurrentBrightness() else {
            // Brightness became (or remains) unavailable
            if brightnessAvailable {
                brightnessAvailable = false
                logger.warning("Lost access to brightness control.")
            }
            return
        }

        // Brightness is available again
        if !brightnessAvailable {
            brightnessAvailable = true
            logger.info("Regained access to brightness control.")
            hasLoggedNoDisplayDetected = false
        }

        // Quantize brightness to 16 steps to match the brightness bars
        let quantizedBrightness = round(brightness * 16.0) / 16.0
        let brightnessChanged = abs(quantizedBrightness - previousBrightness) > 0.001

        if brightnessChanged {
            let delta = quantizedBrightness - previousBrightness
            let currentTime = Date().timeIntervalSince1970
            let timeSinceKeyPress = currentTime - lastBrightnessKeyTime

            let rawBrightness = brightness
            let stepCount = abs(delta) / 0.0625
            logger.debug("Brightness change: \(String(format: "%.4f", delta)) (steps: \(String(format: "%.2f", stepCount))) - Raw: \(String(format: "%.6f", rawBrightness)) -> Quantized: \(String(format: "%.4f", quantizedBrightness)) - Time since key: \(String(format: "%.1f", timeSinceKeyPress))s")

            let isUserChange = isUserInitiatedBrightnessChange(delta, rawBrightness: rawBrightness)

            if isUserChange {
                logger.debug("Showing HUD: \(Int(quantizedBrightness * 100))% (delta: \(delta))")
                currentBrightness = quantizedBrightness
                hudController?.showBrightnessHUD(brightness: quantizedBrightness)
            } else {
                logger.debug("Ignoring ambient/system change: \(Int(quantizedBrightness * 100))% (delta: \(delta), HUD not shown).")
                currentBrightness = quantizedBrightness
            }

            // If accessibility is enabled and we had a recent key press, show HUD even if step detection failed
            if accessibilityEnabled, timeSinceKeyPress < 1.0 {
                if !isUserChange {
                    logger.debug("Showing HUD (accessibility override): \(Int(quantizedBrightness * 100))% (delta: \(delta))")
                    hudController?.showBrightnessHUD(brightness: quantizedBrightness)
                }
            }

            previousBrightness = quantizedBrightness
        }
    }

    @MainActor
    private func handleSystemDefinedEventData(subtype: Int, keyCode: Int, isKeyDown: Bool) {
        // Brightness keys generate NSSystemDefined events with subtype 8
        if subtype == 8 {
            guard isKeyDown else { return }

            // NX key codes: 2 = brightness up, 3 = brightness down
            switch keyCode {
            case 2, 3:
                // Attempt to reduce duplicate logging: both session and HID taps fire for same keypress
                // Due to @MainActor queuing, both may pass this check (race condition), which is fine
                let now = Date().timeIntervalSince1970
                if keyCode == lastHandledKeyCode, now - lastKeyHandleTime < 0.05 {
                    return
                }

                lastHandledKeyCode = keyCode
                lastKeyHandleTime = now

                logger.debug("Brightness key detected: keyCode=\(keyCode) (\(keyCode == 2 ? "up" : "down"))")
                // Track when a brightness key was pressed
                lastBrightnessKeyTime = now
                showHUDForBrightnessKeyPress()
                // Trigger an immediate state check to avoid waiting for the 0.1s polling tick
                checkForBrightnessChange()

            default:
                break
            }
        }
    }

    @MainActor
    private func showHUDForBrightnessKeyPress() {
        // Get fresh brightness value for accurate boundary detection
        guard let brightness = getCurrentBrightness() else { return }
        let quantizedBrightness = round(brightness * 16.0) / 16.0

        // Only show HUD on key presses if we're at brightness boundaries (0% or 100%)
        let atMinBrightness = quantizedBrightness <= 0.001
        let atMaxBrightness = quantizedBrightness >= 0.999

        if !atMinBrightness, !atMaxBrightness { return }

        // Update current brightness and show HUD
        currentBrightness = quantizedBrightness
        hudController?.showBrightnessHUD(brightness: quantizedBrightness)
        logger.debug("Showing HUD for brightness key press at boundary: \(Int(quantizedBrightness * 100))%")
    }
}
