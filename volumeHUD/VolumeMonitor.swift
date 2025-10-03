import AppKit
import AudioToolbox
import AVFoundation
import Combine
import CoreAudio
import Foundation
import IOKit
import Polykit

class VolumeMonitor: ObservableObject, @unchecked Sendable {
    @Published var currentVolume: Float = 0.0
    @Published var isMuted: Bool = false

    /// Set to true to bypass accessibility checks for debugging
    var accessibilityBypassed: Bool = false
    private var audioObjectPropertyAddress: AudioObjectPropertyAddress
    private var isMonitoring = false
    private var accessibilityEnabled: Bool
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var previousVolume: Float = 0.0
    private var previousMuteState: Bool = false
    private var systemEventMonitor: Any?
    private var keyEventMonitor: Any?
    private var lastCapsLockTime: TimeInterval = 0
    private var lastVolumeKeyLogTime: TimeInterval = 0
    private var volumeListenerBlock: ((UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void)?
    private var muteListenerBlock: ((UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void)?
    private var devicePollingTimer: Timer?

    weak var hudController: HUDController?

    let logger = PolyLog()

    init() {
        // Set up the property address for volume changes
        audioObjectPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )

        // Initialize accessibility status
        accessibilityEnabled = AXIsProcessTrusted() && !accessibilityBypassed
    }

    /// Update accessibility status (to be called when permissions change)
    func updateAccessibilityStatus() {
        let newAccessibilityEnabled = AXIsProcessTrusted() && !accessibilityBypassed

        if newAccessibilityEnabled != accessibilityEnabled {
            logger.info("Volume monitor accessibility status changed: \(accessibilityEnabled) -> \(newAccessibilityEnabled)")
            accessibilityEnabled = newAccessibilityEnabled
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Get the default output device
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID,
        )

        guard status == noErr else {
            logger.error("Failed to get default output device.")
            return
        }

        self.deviceID = deviceID

        // Get initial volume without showing HUD
        updateVolumeValuesOnStartup()

        // Register for volume change notifications
        addVolumeListeners()

        // Start monitoring system-defined events for volume key presses
        startSystemEventMonitoring()

        // Monitor for default device changes
        startDefaultDeviceMonitoring()

        isMonitoring = true
        logger.debug("Started monitoring for volume changes.")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        // Remove volume listeners
        removeVolumeListeners()

        // Stop system event monitoring
        stopSystemEventMonitoring()

        // Stop default device monitoring
        stopDefaultDeviceMonitoring()

        isMonitoring = false
        logger.debug("Stopped monitoring for volume changes.")
    }

    private func getCurrentVolumeAndMuteState() -> (volume: Float, isMuted: Bool) {
        // Get volume
        var volume: Float = 0.0
        var size = UInt32(MemoryLayout<Float>.size)

        let volumeStatus = AudioObjectGetPropertyData(
            deviceID,
            &audioObjectPropertyAddress,
            0,
            nil,
            &size,
            &volume,
        )

        var newVolume: Float = currentVolume
        if volumeStatus == noErr {
            // Quantize volume to 16 steps to match the volume bars
            let quantizedVolume = round(volume * 16.0) / 16.0
            newVolume = quantizedVolume
        }

        // Get mute state
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )

        let muteStatus = AudioObjectGetPropertyData(
            deviceID,
            &muteAddress,
            0,
            nil,
            &size,
            &muted,
        )

        var newMuted: Bool = isMuted
        if muteStatus == noErr {
            newMuted = muted != 0
        }

        return (volume: newVolume, isMuted: newMuted)
    }

    private func updateVolumeValuesOnStartup() {
        let (newVolume, newMuted) = getCurrentVolumeAndMuteState()

        // Update @Published properties directly
        currentVolume = newVolume
        isMuted = newMuted

        // Set previous values to current values to prevent initial HUD display
        previousVolume = newVolume
        previousMuteState = newMuted

        logger.debug("Initial volume set: \(Int(newVolume * 100))%, Muted: \(newMuted)")
    }

    private func updateVolumeValues() {
        let (newVolume, newMuted) = getCurrentVolumeAndMuteState()

        // Check if volume or mute state changed
        let volumeChanged = abs(newVolume - previousVolume) > 0.001 // Smaller threshold for more responsiveness
        let muteChanged = newMuted != previousMuteState

        if volumeChanged || muteChanged {
            logger.debug("Volume updated: \(Int(newVolume * 100))%, Muted: \(newMuted)")

            // Update @Published properties and show HUD
            currentVolume = newVolume
            isMuted = newMuted
            DispatchQueue.main.async {
                self.hudController?.showVolumeHUD(volume: newVolume, isMuted: newMuted)
            }

            // Update previous values
            previousVolume = newVolume
            previousMuteState = newMuted
        }
    }

    // MARK: Key Press Monitoring

    private func startSystemEventMonitoring() {
        if !accessibilityEnabled {
            logger.info("Accessibility permissions not granted, so volume keys cannot be detected.")
            return
        }

        // Monitor system-defined events for volume key presses
        systemEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            guard let self else { return }
            // Extract only primitive fields on the monitoring thread to avoid
            // crossing threads with non-Sendable NSEvent
            let subtype = Int(event.subtype.rawValue)
            let data1 = Int(event.data1)
            let keyCode = (data1 & 0xFFFF_0000) >> 16
            let keyFlags = data1 & 0x0000_FFFF
            let keyState = (keyFlags & 0xFF00) >> 8 // 0x0A = keyDown, 0x0B = keyUp
            let isKeyDown = keyState == 0x0A

            Task { @MainActor [weak self] in
                guard let self else { return }
                handleSystemDefinedEventData(
                    subtype: subtype, keyCode: keyCode, keyPressed: (keyFlags & 0xFF00) >> 8,
                    isKeyDown: isKeyDown,
                )
            }
        }

        // Also monitor key events to catch volume keys that might not generate system-defined events
        keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { _ in }

        logger.debug("Started monitoring system-defined events for volume keys.")
    }

    private func stopSystemEventMonitoring() {
        if let monitor = systemEventMonitor {
            NSEvent.removeMonitor(monitor)
            systemEventMonitor = nil
            logger.debug("Stopped monitoring system-defined events.")
        }
        if let keyMonitor = keyEventMonitor {
            NSEvent.removeMonitor(keyMonitor)
            keyEventMonitor = nil
        }
    }

    @MainActor
    private func handleSystemDefinedEventData(subtype: Int, keyCode: Int, keyPressed _: Int, isKeyDown: Bool) {
        let currentTime = Date().timeIntervalSince1970

        // Track Caps Lock events
        if subtype == 211 {
            lastCapsLockTime = currentTime
            logger.debug("Caps Lock event detected, ignoring volume events for 0.5 seconds.")
            return
        }

        // Volume keys generate NSSystemDefined events with subtype 8
        if subtype == 8 {
            // Ignore volume events that happen within 0.5 seconds of Caps Lock
            if currentTime - lastCapsLockTime < 0.5 {
                logger.debug("Ignoring volume event, too close to Caps Lock.")
                return
            }

            guard isKeyDown else { return }

            // NX key codes: 0 = vol up, 1 = vol down, 7 = mute
            switch keyCode {
            case 1: // Volume down
                showHUDForVolumeKeyPress(isVolumeUp: false)
            case 0: // Volume up
                showHUDForVolumeKeyPress(isVolumeUp: true)
            default:
                break
            }
        }
    }

    @MainActor
    private func showHUDForVolumeKeyPress(isVolumeUp: Bool) {
        // Avoid CoreAudio calls during key event; use cached state
        let currentVol = currentVolume
        let currentMuted = isMuted

        // Only show HUD on key presses if we're at volume boundaries (0% or 100%)
        // This prevents media keys from triggering the HUD when volume is between 1-99%
        let atMinVolume = currentVol <= 0.001
        let atMaxVolume = currentVol >= 0.999

        if !atMinVolume, !atMaxVolume {
            let currentTime = Date().timeIntervalSince1970
            // Debounce log messages as macOS seems to fire key events twice
            if currentTime - lastVolumeKeyLogTime > 0.1 {
                lastVolumeKeyLogTime = currentTime
            }
            return
        }

        // Show HUD with current state
        hudController?.showVolumeHUD(volume: currentVol, isMuted: currentMuted)

        logger.debug("Showing HUD for volume \(isVolumeUp ? "up" : "down") key press at boundary, current volume: \(Int(currentVol * 100))%, muted: \(currentMuted)")
    }

    // MARK: Device Change Monitoring

    private func startDefaultDeviceMonitoring() {
        devicePollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForDeviceChange()
            }
        }
        logger.debug("Polling for changes to the default output device.")
    }

    private func stopDefaultDeviceMonitoring() {
        devicePollingTimer?.invalidate()
        devicePollingTimer = nil
        logger.debug("Stopped device monitoring.")
    }

    private func checkForDeviceChange() {
        // Get current default device
        var currentDeviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &currentDeviceID,
        )

        guard status == noErr else { return }

        // Check if device changed
        if currentDeviceID != deviceID {
            logger.debug("Default output device changed: \(deviceID) -> \(currentDeviceID)")
            handleDefaultDeviceChanged()
        }
    }

    private func handleDefaultDeviceChanged() {
        logger.debug("Re-registering volume listeners on device change.")

        // Remove old listeners
        removeVolumeListeners()

        // Get new default device
        var newDeviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &newDeviceID,
        )

        guard status == noErr else {
            logger.error("Failed to get new default output device.")
            return
        }

        // Update device ID
        deviceID = newDeviceID

        // Add new listeners
        addVolumeListeners()

        // Update volume values for the new device
        DispatchQueue.main.async {
            self.updateVolumeValuesOnStartup()
        }

        logger.debug("Successfully switched to new device: \(newDeviceID)")
    }

    private func removeVolumeListeners() {
        if let block = volumeListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &audioObjectPropertyAddress,
                DispatchQueue.main,
                block,
            )
            volumeListenerBlock = nil
        }

        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )
        if let block = muteListenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &muteAddress,
                DispatchQueue.main,
                block,
            )
            muteListenerBlock = nil
        }
    }

    private func addVolumeListeners() {
        // Register for volume change notifications using block on main queue
        volumeListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.updateVolumeValues()
            }
        }
        if let block = volumeListenerBlock {
            AudioObjectAddPropertyListenerBlock(
                deviceID,
                &audioObjectPropertyAddress,
                DispatchQueue.main,
                block,
            )
        }

        // Also monitor mute state
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )
        muteListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.updateVolumeValues()
            }
        }
        if let block = muteListenerBlock {
            AudioObjectAddPropertyListenerBlock(
                deviceID,
                &muteAddress,
                DispatchQueue.main,
                block,
            )
        }
    }
}
