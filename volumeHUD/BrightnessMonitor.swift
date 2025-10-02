import AppKit
import Combine
import CoreGraphics
import Foundation
import IOKit
import IOKit.pwr_mgt
import Polykit

class BrightnessMonitor: ObservableObject, @unchecked Sendable {
    @Published var currentBrightness: Float = 0.0

    /// Set to true to bypass accessibility checks for debugging
    var accessibilityBypassed: Bool = false
    let accessibilityGranted = AXIsProcessTrusted()
    private var accessibilityEnabled: Bool

    private var isMonitoring = false
    private var previousBrightness: Float = 0.0
    private var brightnessPollingTimer: Timer?
    private var systemEventMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var lastBrightnessKeyTime: TimeInterval = 0
    private var lastBrightnessKeyEventSeenTime: TimeInterval = 0
    private var receivedAnyBrightnessKeyEvent = false
    private var hasLoggedBrightnessError = false
    private var brightnessAvailable = false
    private var lastBrightnessChangeTime: TimeInterval = 0
    private var brightnessChangeCount = 0
    private var heuristicShowTimer: Timer?

    /// Cache DisplayServices function pointers
    private var displayServicesHandle: UnsafeMutableRawPointer?
    private var canChangeBrightnessFunc: (@convention(c) (CGDirectDisplayID) -> Bool)?
    private var getBrightnessFunc: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> kern_return_t)?

    weak var hudController: HUDController?

    let logger = PolyLog()

    init() {
        // Initialize with a timestamp far in the past so initial startup doesn't show HUD
        lastBrightnessKeyTime = 0

        // Enable accessibility if it's granted and not bypassed for debugging
        accessibilityEnabled = accessibilityGranted && !accessibilityBypassed

        // Log the accessibility status for debugging
        if accessibilityBypassed { logger.warning("Accessibility bypass enabled. Relying on heuristics only for brightness debugging.") }

        // Load DisplayServices framework once at initialization
        loadDisplayServices()
    }

    deinit {}

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

        guard let canChangeBrightnessPtr = dlsym(handle, "DisplayServicesCanChangeBrightness"),
              let getBrightnessPtr = dlsym(handle, "DisplayServicesGetBrightness")
        else {
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

    func startMonitoring() {
        guard !isMonitoring else { return }

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
        heuristicShowTimer?.invalidate()
        heuristicShowTimer = nil

        isMonitoring = false
        logger.debug("Stopped monitoring for brightness changes.")
    }

    private func updateBrightnessOnStartup() {
        if let brightness = getCurrentBrightness() {
            // Quantize brightness to 16 steps to match the brightness bars
            let quantizedBrightness = round(brightness * 16.0) / 16.0
            currentBrightness = quantizedBrightness
            previousBrightness = quantizedBrightness
            brightnessAvailable = true
            logger.info("Initial brightness set: \(Int(quantizedBrightness * 100))%")
        } else {
            brightnessAvailable = false
            if !hasLoggedBrightnessError {
                logger.error("Brightness control not available; this may be an external display or a system without brightness control.")
                hasLoggedBrightnessError = true
            }
        }
    }

    private func getCurrentBrightness() -> Float? {
        // Use cached DisplayServices function pointers
        guard let canChangeBrightness = canChangeBrightnessFunc,
              let getBrightness = getBrightnessFunc
        else {
            logger.error("getCurrentBrightness: function pointers not available.")
            return nil
        }

        let mainDisplay = CGMainDisplayID()
        let canChange = canChangeBrightness(mainDisplay)

        guard canChange else {
            logger.error("getCurrentBrightness: canChangeBrightness returned false for display \(mainDisplay)")
            return nil
        }

        var brightness: Float = 0.0
        let result = getBrightness(mainDisplay, &brightness)

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
            logger.debug("Stopped monitoring system-defined events (NSEvent).")
        }
    }

    private func startEventTap() {
        // Install a CGEvent tap to reliably observe NX_SYSDEFINED events without capturing context
        let systemDefinedMask: CGEventMask = 1 << 14 // kCGEventSystemDefined = 14
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: systemDefinedMask,
            callback: { _, type, cgEvent, opaqueInfo -> Unmanaged<CGEvent>? in
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
        ) else {
            logger.warning("Failed to create CGEvent tap for systemDefined events; falling back to NSEvent only.")
            return
        }

        eventTap = tap
        eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = eventTapRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            logger.debug("Started CGEvent tap for systemDefined events.")
        } else {
            logger.warning("Failed to create run loop source for event tap.")
        }
    }

    private func stopEventTap() {
        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTapRunLoopSource = nil
        eventTap = nil
        logger.debug("Stopped CGEvent tap for systemDefined events.")
    }

    @MainActor
    private func checkForBrightnessChange() {
        // Skip polling if brightness isn't available
        guard brightnessAvailable else { return }

        guard let brightness = getCurrentBrightness() else {
            // Brightness became unavailable
            if brightnessAvailable {
                brightnessAvailable = false
                logger.error("Lost access to brightness control.")
            }
            return
        }

        // Brightness is available again
        if !brightnessAvailable {
            brightnessAvailable = true
            logger.info("Regained access to brightness control.")
        }

        // Quantize brightness to 16 steps to match the brightness bars
        let quantizedBrightness = round(brightness * 16.0) / 16.0
        let brightnessChanged = abs(quantizedBrightness - previousBrightness) > 0.001

        if brightnessChanged {
            // Check if this change happened within a short window after a key press
            let currentTime = Date().timeIntervalSince1970
            let timeSinceKeyPress = currentTime - lastBrightnessKeyTime

            // Track brightness change frequency for ambient light detection
            let timeSinceLastChange = currentTime - lastBrightnessChangeTime
            if timeSinceLastChange < 3.0 { // Changes within 3 seconds (increased window)
                brightnessChangeCount += 1
            } else {
                brightnessChangeCount = 1 // Reset counter for new change sequence
            }
            lastBrightnessChangeTime = currentTime

            // Step magnitude in 1/16th bars
            let deltaSteps = abs(quantizedBrightness - previousBrightness) * 16.0

            // Determine if this is likely an ambient light adjustment
            // Ambient light changes tend to happen in rapid sequences (>1 change in quick succession)
            // Also consider single changes that happen shortly after other changes
            // Additionally, treat large instantaneous jumps as ambient when no key press is recent
            let isLikelyAmbientLight = (brightnessChangeCount > 1 && timeSinceKeyPress > 0.5) ||
                (timeSinceLastChange < 0.5 && timeSinceKeyPress > 0.5) ||
                (deltaSteps >= 2.0 && timeSinceKeyPress > 0.5)

            // If we can observe key events or have Accessibility, rely solely on key presses
            if receivedAnyBrightnessKeyEvent || accessibilityEnabled {
                if timeSinceKeyPress < 1.0 {
                    logger.info("Brightness updated (key press): \(Int(quantizedBrightness * 100))%")
                    currentBrightness = quantizedBrightness
                    hudController?.showBrightnessHUD(brightness: quantizedBrightness)
                } else {
                    logger.debug("Brightness auto-adjusted to \(Int(quantizedBrightness * 100))% (key-gated, no recent key press, HUD not shown).")
                    currentBrightness = quantizedBrightness
                }
            } else {
                // Heuristic mode (no permissions and no key events): use delay and spike detection to avoid flashes
                if isLikelyAmbientLight {
                    heuristicShowTimer?.invalidate()
                    heuristicShowTimer = nil
                    logger.debug("Brightness auto-adjusted to \(Int(quantizedBrightness * 100))% (ambient light change, HUD not shown).")
                    currentBrightness = quantizedBrightness
                } else {
                    heuristicShowTimer?.invalidate()
                    let scheduledChangeCount = brightnessChangeCount
                    let scheduledLastChangeTime = lastBrightnessChangeTime
                    let scheduledBrightness = quantizedBrightness

                    heuristicShowTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            let hasConfirmingChange = (brightnessChangeCount >= scheduledChangeCount + 1)
                            let withinSameWindow = abs(lastBrightnessChangeTime - scheduledLastChangeTime) < 0.001
                            if hasConfirmingChange, withinSameWindow {
                                logger.info("Brightness updated (heuristic): \(Int(scheduledBrightness * 100))%")
                                currentBrightness = scheduledBrightness
                                hudController?.showBrightnessHUD(brightness: scheduledBrightness)
                            } else {
                                logger.debug("Skipped HUD show (no confirming change; likely ambient).")
                            }
                        }
                    }
                    currentBrightness = quantizedBrightness
                }
            }

            previousBrightness = quantizedBrightness
        }
    }

    @MainActor
    private func handleSystemDefinedEventData(subtype: Int, keyCode: Int, isKeyDown: Bool) {
        // Brightness keys generate NSSystemDefined events with subtype 8 (logging is noisy)
        // logger.debug("System event: subtype=\(subtype), keyCode=\(keyCode), isKeyDown=\(isKeyDown)")
        if subtype == 8 {
            guard isKeyDown else { return }

            // NX key codes: 2 = brightness down, 3 = brightness up
            switch keyCode {
            case 2, 3:
                logger.debug("Brightness key detected: \(keyCode == 2 ? "brightness down" : "brightness up")")
                // Track when a brightness key was pressed and that we can observe key events
                lastBrightnessKeyTime = Date().timeIntervalSince1970
                lastBrightnessKeyEventSeenTime = lastBrightnessKeyTime
                receivedAnyBrightnessKeyEvent = true
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

        if !atMinBrightness, !atMaxBrightness {
            logger.debug("HUD not forced for brightness key because brightness is not 0% or 100%.")
            return
        }

        // Update current brightness and show HUD
        currentBrightness = quantizedBrightness
        hudController?.showBrightnessHUD(brightness: quantizedBrightness)
        logger.debug("Showing HUD for brightness key press at boundary: \(Int(quantizedBrightness * 100))%")
    }
}
