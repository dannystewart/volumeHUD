import AppKit
import Combine
import CoreGraphics
import Foundation
import IOKit
import IOKit.pwr_mgt
import Polykit

class BrightnessMonitor: ObservableObject, @unchecked Sendable {
    @Published var currentBrightness: Float = 0.0

    private var isMonitoring = false
    private var previousBrightness: Float = 0.0
    private var brightnessPollingTimer: Timer?
    private var systemEventMonitor: Any?
    private var lastBrightnessKeyTime: TimeInterval = 0
    private var hasLoggedBrightnessError = false
    private var brightnessAvailable = false

    weak var hudController: HUDController?

    let logger = PolyLog()

    init() {
        // Initialize brightness monitoring
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Get initial brightness without showing HUD
        updateBrightnessOnStartup()

        // Start polling for brightness changes
        startBrightnessPolling()

        // Start monitoring system-defined events for brightness key presses
        startSystemEventMonitoring()

        isMonitoring = true
        logger.debug("Started monitoring for brightness changes.")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        // Stop polling
        stopBrightnessPolling()

        // Stop system event monitoring
        stopSystemEventMonitoring()

        isMonitoring = false
        logger.debug("Stopped monitoring for brightness changes.")
    }

    private func updateBrightnessOnStartup() {
        if let brightness = getCurrentBrightness() {
            currentBrightness = brightness
            previousBrightness = brightness
            brightnessAvailable = true
            logger.info("Initial brightness set: \(Int(brightness * 100))%")
        } else {
            brightnessAvailable = false
            if !hasLoggedBrightnessError {
                logger.error("Brightness control not available; this may be an external display or a system without brightness control.")
                hasLoggedBrightnessError = true
            }
        }
    }

    private func getCurrentBrightness() -> Float? {
        // Use DisplayServices private framework via dynamic loading
        typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> kern_return_t
        typealias CanChangeBrightnessFunc = @convention(c) (CGDirectDisplayID) -> Bool

        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            return nil
        }

        defer { dlclose(handle) }

        guard let canChangeBrightnessPtr = dlsym(handle, "DisplayServicesCanChangeBrightness"),
              let getBrightnessPtr = dlsym(handle, "DisplayServicesGetBrightness")
        else {
            return nil
        }

        let canChangeBrightness = unsafeBitCast(canChangeBrightnessPtr, to: CanChangeBrightnessFunc.self)
        let getBrightness = unsafeBitCast(getBrightnessPtr, to: GetBrightnessFunc.self)

        let mainDisplay = CGMainDisplayID()

        guard canChangeBrightness(mainDisplay) else {
            return nil
        }

        var brightness: Float = 0.0
        let result = getBrightness(mainDisplay, &brightness)

        if result == KERN_SUCCESS {
            return brightness
        }

        return nil
    }

    private func getDisplayServices() -> io_service_t? {
        // This method is no longer needed
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
                self.handleSystemDefinedEventData(
                    subtype: subtype, keyCode: keyCode, isKeyDown: isKeyDown
                )
            }
        }

        logger.debug("Started monitoring system-defined events for brightness keys.")
    }

    private func stopSystemEventMonitoring() {
        if let monitor = systemEventMonitor {
            NSEvent.removeMonitor(monitor)
            systemEventMonitor = nil
            logger.debug("Stopped monitoring system-defined events.")
        }
    }

    @MainActor
    private func checkForBrightnessChange() {
        // Skip polling if brightness isn't available
        guard brightnessAvailable else { return }

        guard let newBrightness = getCurrentBrightness() else {
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

        let brightnessChanged = abs(newBrightness - previousBrightness) > 0.001

        if brightnessChanged {
            logger.info("Brightness updated: \(Int(newBrightness * 100))%")

            currentBrightness = newBrightness
            hudController?.showBrightnessHUD(brightness: newBrightness)

            previousBrightness = newBrightness
        }
    }

    @MainActor
    private func handleSystemDefinedEventData(subtype: Int, keyCode: Int, isKeyDown: Bool) {
        // Brightness keys generate NSSystemDefined events with subtype 8
        if subtype == 8 {
            guard isKeyDown else { return }

            // NX key codes: 2 = brightness down, 3 = brightness up
            switch keyCode {
            case 2, 3:
                showHUDForBrightnessKeyPress()
            default:
                break
            }
        }
    }

    @MainActor
    private func showHUDForBrightnessKeyPress() {
        let currentBright = currentBrightness

        // Only show HUD on key presses if we're at brightness boundaries (0% or 100%)
        let atMinBrightness = currentBright <= 0.001
        let atMaxBrightness = currentBright >= 0.999

        if !atMinBrightness, !atMaxBrightness {
            logger.debug("Brightness key press ignored because brightness is not at boundary.")
            return
        }

        hudController?.showBrightnessHUD(brightness: currentBright)
        logger.debug("Showing HUD for brightness key press at boundary: \(Int(currentBright * 100))%")
    }
}
