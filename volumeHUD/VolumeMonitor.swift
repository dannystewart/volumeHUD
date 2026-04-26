//
//  VolumeMonitor.swift
//  by Danny Stewart (2025)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import AppKit
import AudioToolbox
import AVFoundation
import Combine
import CoreAudio
import Foundation
import IOKit

class VolumeMonitor: ObservableObject, @unchecked Sendable {
    private struct VolumeSnapshot {
        let rawVolume: Float
        let displayVolume: Float
        let isMuted: Bool
    }

    @Published var currentVolume: Float = 0.0
    @Published var isMuted: Bool = false

    weak var hudController: HUDController?
    #if !SANDBOX
        weak var mediaKeyInterceptor: MediaKeyInterceptor?
    #endif // !SANDBOX

    let logger: Logger = .init()

    private var audioObjectPropertyAddress: AudioObjectPropertyAddress
    private var isMonitoring = false
    private var accessibilityEnabled: Bool
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var lastVolumeKeyTime: TimeInterval = 0
    private var lastMuteKeyTime: TimeInterval = 0
    private var previousRawVolume: Float = 0.0
    private var previousMuteState: Bool = false
    #if !SANDBOX
        private var systemEventMonitor: Any?
        private var keyEventMonitor: Any?
        private var eventTap: CFMachPort?
        private var eventTapRunLoopSource: CFRunLoopSource?
        private var hidEventTap: CFMachPort?
        private var hidEventTapRunLoopSource: CFRunLoopSource?
        private var lastCapsLockTime: TimeInterval = 0
        private var lastHandledKeyCode: Int = -1
        private var lastKeyHandleTime: TimeInterval = 0
        private var lastVolumeKeyLogTime: TimeInterval = 0
    #endif // !SANDBOX
    private var volumeListenerBlock: ((UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void)?
    private var muteListenerBlock: ((UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void)?
    private var devicePollingTimer: Timer?
    private let isPreviewMode: Bool
    private var isOptionShiftHeld: Bool = false

    init(isPreviewMode: Bool = false) {
        self.isPreviewMode = isPreviewMode

        // Set up the property address for volume changes
        audioObjectPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )

        // Skip expensive accessibility check in preview mode
        if isPreviewMode {
            accessibilityEnabled = false
            currentVolume = 0.5
            isMuted = false
        } else {
            // Initialize accessibility status
            accessibilityEnabled = AXIsProcessTrusted()
        }
    }

    /// Update accessibility status (to be called when permissions change)
    func updateAccessibilityStatus() {
        let newAccessibilityEnabled = AXIsProcessTrusted()

        if newAccessibilityEnabled != accessibilityEnabled {
            logger.info("Volume monitor accessibility status changed: \(accessibilityEnabled) -> \(newAccessibilityEnabled)")
            accessibilityEnabled = newAccessibilityEnabled
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Skip all monitoring in preview mode
        if isPreviewMode {
            logger.debug("Skipping volume monitoring in preview mode.")
            isMonitoring = true
            return
        }

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

        #if !SANDBOX
            // Start monitoring system-defined events for volume key presses
            startSystemEventMonitoring()
        #endif // !SANDBOX

        // Monitor for default device changes
        startDefaultDeviceMonitoring()

        isMonitoring = true
        logger.debug("Started monitoring for volume changes.")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        // Remove volume listeners
        removeVolumeListeners()

        #if !SANDBOX
            // Stop system event monitoring
            stopSystemEventMonitoring()
        #endif // !SANDBOX

        // Stop default device monitoring
        stopDefaultDeviceMonitoring()

        isMonitoring = false
        logger.debug("Stopped monitoring for volume changes.")
    }

    private func isAlignedToStep(_ value: Float, stepCount: Float, tolerance: Float = 0.01) -> Bool {
        let scaledValue = value * stepCount
        return abs(scaledValue - round(scaledValue)) < tolerance
    }

    private func preferredVolumeStepCount(for rawVolume: Float) -> Float {
        if isOptionShiftHeld {
            return 64.0
        }

        if isAlignedToStep(rawVolume, stepCount: 16.0) {
            return 16.0
        }

        if isAlignedToStep(rawVolume, stepCount: 64.0) {
            return 64.0
        }

        return 16.0
    }

    private func isUserInitiatedVolumeChange(_ delta: Float, rawVolume: Float) -> Bool {
        let tolerance: Float = 0.001
        let absDelta = abs(delta)
        let supportedStepCounts: [Float] = [16.0, 64.0]

        for stepCount in supportedStepCounts {
            let baseStepSize = 1.0 / stepCount
            for multiplier in 1 ... 4 {
                let expectedDelta = baseStepSize * Float(multiplier)
                if abs(absDelta - expectedDelta) < tolerance, isAlignedToStep(rawVolume, stepCount: stepCount) {
                    return true
                }
            }
        }

        return false
    }

    private func getCurrentVolumeAndMuteState() -> VolumeSnapshot {
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

        var rawVolume: Float = previousRawVolume
        var newVolume: Float = currentVolume
        if volumeStatus == noErr {
            rawVolume = volume
            let steps = preferredVolumeStepCount(for: rawVolume)
            let quantizedVolume = round(rawVolume * steps) / steps
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

        return VolumeSnapshot(rawVolume: rawVolume, displayVolume: newVolume, isMuted: newMuted)
    }

    private func updateVolumeValuesOnStartup() {
        let snapshot = getCurrentVolumeAndMuteState()

        // Update @Published properties directly
        currentVolume = snapshot.displayVolume
        isMuted = snapshot.isMuted

        // Set previous values to current values to prevent initial HUD display
        previousRawVolume = snapshot.rawVolume
        previousMuteState = snapshot.isMuted

        logger.debug("Initial volume set: \(Int(snapshot.displayVolume * 100))%, Muted: \(snapshot.isMuted)")
    }

    private func updateVolumeValues() {
        let snapshot = getCurrentVolumeAndMuteState()
        let newVolume = snapshot.displayVolume
        let newMuted = snapshot.isMuted
        let rawVolumeDelta = snapshot.rawVolume - previousRawVolume

        // Check if volume or mute state changed
        let volumeChanged = abs(rawVolumeDelta) > 0.001
        let muteChanged = newMuted != previousMuteState

        if volumeChanged || muteChanged {
            logger.debug("Volume updated: \(Int(newVolume * 100))%, Muted: \(newMuted)")

            // Update @Published properties
            currentVolume = newVolume
            isMuted = newMuted

            let currentTime = Date().timeIntervalSince1970
            let timeSinceVolumeKey = currentTime - lastVolumeKeyTime
            let timeSinceMuteKey = currentTime - lastMuteKeyTime
            let userVolumeHeuristicMatched = volumeChanged && isUserInitiatedVolumeChange(rawVolumeDelta, rawVolume: snapshot.rawVolume)
            let hasRecentVolumeKeyEvidence = timeSinceVolumeKey < 1.0
            let hasRecentMuteKeyEvidence = timeSinceMuteKey < 1.0

            // MediaKeyInterceptor already showed the HUD for intercepted changes.
            let shouldShowHUD: Bool
            let showReason: String
            #if !SANDBOX
                if let interceptor = mediaKeyInterceptor {
                    let timeSinceInterceptorChange = Date().timeIntervalSince1970 - interceptor.lastVolumeChangeTime
                    if timeSinceInterceptorChange <= MediaKeyInterceptor.volumeChangeCooldown {
                        shouldShowHUD = false
                        showReason = "Suppressing duplicate HUD because MediaKeyInterceptor already handled this change."
                    } else if volumeChanged, userVolumeHeuristicMatched || hasRecentVolumeKeyEvidence {
                        shouldShowHUD = true
                        showReason = userVolumeHeuristicMatched
                            ? "Showing HUD because the volume delta matched user key step patterns."
                            : "Showing HUD because a recent volume key press corroborated the CoreAudio change."
                    } else if muteChanged, hasRecentMuteKeyEvidence {
                        shouldShowHUD = true
                        showReason = "Showing HUD because a recent mute key press corroborated the mute change."
                    } else {
                        shouldShowHUD = false
                        showReason = "Ignoring non-user volume or mute change with no corroborating key evidence."
                    }
                } else {
                    if volumeChanged, userVolumeHeuristicMatched || hasRecentVolumeKeyEvidence {
                        shouldShowHUD = true
                        showReason = userVolumeHeuristicMatched
                            ? "Showing HUD because the volume delta matched user key step patterns."
                            : "Showing HUD because a recent volume key press corroborated the CoreAudio change."
                    } else if muteChanged, hasRecentMuteKeyEvidence {
                        shouldShowHUD = true
                        showReason = "Showing HUD because a recent mute key press corroborated the mute change."
                    } else {
                        shouldShowHUD = false
                        showReason = "Ignoring non-user volume or mute change with no corroborating key evidence."
                    }
                }
            #else
                if volumeChanged, userVolumeHeuristicMatched {
                    shouldShowHUD = true
                    showReason = "Showing HUD because the volume delta matched user key step patterns."
                } else {
                    shouldShowHUD = false
                    showReason = "Ignoring volume or mute change without heuristic evidence in sandbox mode."
                }
            #endif // !SANDBOX

            if shouldShowHUD {
                logger.debug(showReason)
                DispatchQueue.main.async {
                    self.hudController?.showVolumeHUD(volume: newVolume, isMuted: newMuted)
                }
            } else {
                logger.debug(showReason)
            }

            // Update previous values
            previousRawVolume = snapshot.rawVolume
            previousMuteState = newMuted
        }
    }

    #if !SANDBOX

        // MARK: Key Press Monitoring

        private func startSystemEventMonitoring() {
            // Monitor system-defined events for volume key presses
            systemEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
                guard let self else { return }
                // Extract only primitive fields on the monitoring thread to avoid crossing threads
                // with non-Sendable NSEvent.
                let subtype = Int(event.subtype.rawValue)
                let data1 = Int(event.data1)
                let keyCode = (data1 & 0xFFFF_0000) >> 16
                let keyFlags = data1 & 0x0000_FFFF
                let keyState = (keyFlags & 0xFF00) >> 8 // 0x0A = keyDown, 0x0B = keyUp
                let isKeyDown = keyState == 0x0A
                let modifierFlags = event.modifierFlags

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    handleSystemDefinedEventData(
                        subtype: subtype,
                        keyCode: keyCode,
                        keyPressed: (keyFlags & 0xFF00) >> 8,
                        isKeyDown: isKeyDown,
                        modifierFlags: modifierFlags,
                    )
                }
            }

            // Also monitor key events to catch keys that may not generate system-defined events.
            keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { _ in }

            startEventTap()

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

            stopEventTap()
        }

        private func startEventTap() {
            let systemDefinedMask: CGEventMask = 1 << 14
            let userInfo = Unmanaged.passUnretained(self).toOpaque()

            guard
                let tap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .listenOnly,
                    eventsOfInterest: systemDefinedMask,
                    callback: { _, type, cgEvent, opaqueInfo -> Unmanaged<CGEvent>? in
                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            if let opaqueInfo {
                                let monitor = Unmanaged<VolumeMonitor>.fromOpaque(opaqueInfo).takeUnretainedValue()
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
                        let monitor = Unmanaged<VolumeMonitor>.fromOpaque(opaqueInfo).takeUnretainedValue()
                        let subtype = Int(nsEvent.subtype.rawValue)
                        let data1 = Int(nsEvent.data1)
                        let keyCode = (data1 & 0xFFFF_0000) >> 16
                        let keyFlags = data1 & 0x0000_FFFF
                        let keyState = (keyFlags & 0xFF00) >> 8
                        let isKeyDown = keyState == 0x0A
                        let modifierFlags = nsEvent.modifierFlags

                        Task { @MainActor in
                            monitor.handleSystemDefinedEventData(
                                subtype: subtype,
                                keyCode: keyCode,
                                keyPressed: keyState,
                                isKeyDown: isKeyDown,
                                modifierFlags: modifierFlags,
                            )
                        }

                        return Unmanaged.passUnretained(cgEvent)
                    },
                    userInfo: userInfo,
                ) else
            {
                logger.warning("Failed to create CGEvent tap for volume keys; falling back to NSEvent monitoring only.")
                return
            }

            eventTap = tap
            eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = eventTapRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.debug("Started CGEvent tap (session-level) for volume keys.")
            } else {
                logger.warning("Failed to create run loop source for volume key event tap.")
            }

            if
                let hidTap = CGEvent.tapCreate(
                    tap: .cghidEventTap,
                    place: .headInsertEventTap,
                    options: .listenOnly,
                    eventsOfInterest: systemDefinedMask,
                    callback: { _, type, cgEvent, opaqueInfo -> Unmanaged<CGEvent>? in
                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            if let opaqueInfo {
                                let monitor = Unmanaged<VolumeMonitor>.fromOpaque(opaqueInfo).takeUnretainedValue()
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
                        let monitor = Unmanaged<VolumeMonitor>.fromOpaque(opaqueInfo).takeUnretainedValue()
                        let subtype = Int(nsEvent.subtype.rawValue)
                        let data1 = Int(nsEvent.data1)
                        let keyCode = (data1 & 0xFFFF_0000) >> 16
                        let keyFlags = data1 & 0x0000_FFFF
                        let keyState = (keyFlags & 0xFF00) >> 8
                        let isKeyDown = keyState == 0x0A
                        let modifierFlags = nsEvent.modifierFlags

                        Task { @MainActor in
                            monitor.handleSystemDefinedEventData(
                                subtype: subtype,
                                keyCode: keyCode,
                                keyPressed: keyState,
                                isKeyDown: isKeyDown,
                                modifierFlags: modifierFlags,
                            )
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
                    logger.debug("Started CGEvent tap (HID-level) for volume keys.")
                } else {
                    logger.warning("Failed to create run loop source for HID-level volume key event tap.")
                }
            } else {
                logger.debug("HID-level volume key event tap unavailable; relying on session-level tap only.")
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

        @MainActor
        private func handleSystemDefinedEventData(subtype: Int, keyCode: Int, keyPressed _: Int, isKeyDown: Bool, modifierFlags: NSEvent.ModifierFlags = []) {
            let currentTime = Date().timeIntervalSince1970

            // Check if Option+Shift is held for finer volume control (1/64 instead of 1/16)
            isOptionShiftHeld = modifierFlags.contains(.option) && modifierFlags.contains(.shift)

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

                if keyCode == lastHandledKeyCode, currentTime - lastKeyHandleTime < 0.05 {
                    return
                }

                lastHandledKeyCode = keyCode
                lastKeyHandleTime = currentTime

                // NX key codes: 0 = vol up, 1 = vol down, 7 = mute
                switch keyCode {
                case 1: // Volume down
                    lastVolumeKeyTime = currentTime
                    showHUDForVolumeKeyPress(isVolumeUp: false)

                case 0: // Volume up
                    lastVolumeKeyTime = currentTime
                    showHUDForVolumeKeyPress(isVolumeUp: true)

                case 7: // Mute
                    lastMuteKeyTime = currentTime
                    logger.debug("Mute key detected.")

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

            // Only show HUD on key presses if we're at volume boundaries (0% or 100%) This prevents
            // media keys from triggering the HUD when volume is between 1-99%
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
    #endif // !SANDBOX

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
