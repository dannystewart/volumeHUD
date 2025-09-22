//
//  VolumeMonitor.swift
//  volumeHUD
//
//  Created by Danny Stewart on 9/21/25.
//

import AVFoundation
import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Foundation
import IOKit
import PolyLog

class VolumeMonitor: ObservableObject, @unchecked Sendable {
    @Published var currentVolume: Float = 0.0
    @Published var isMuted: Bool = false

    private var audioObjectPropertyAddress: AudioObjectPropertyAddress
    private var isMonitoring = false
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var previousVolume: Float = 0.0
    private var previousMuteState: Bool = false
    private var systemEventMonitor: Any?
    private var keyEventMonitor: Any?
    private var lastCapsLockTime: TimeInterval = 0
    private var lastVolumeKeyLogTime: TimeInterval = 0
    private var defaultDeviceListenerAdded = false

    weak var hudController: HUDController?

    let logger = PolyLog.getLogger("VolumeMonitor")

    init() {
        // Set up the property address for volume changes
        audioObjectPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Get the default output device
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
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
        logger.info("Started monitoring volume changes.")
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
        logger.info("Stopped monitoring volume changes.")
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
            &volume
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
            mElement: kAudioObjectPropertyElementMain
        )

        let muteStatus = AudioObjectGetPropertyData(
            deviceID,
            &muteAddress,
            0,
            nil,
            &size,
            &muted
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

        logger.info("Initial volume set: \(Int(newVolume * 100))%, Muted: \(newMuted)")
    }

    private func updateVolumeValues() {
        let (newVolume, newMuted) = getCurrentVolumeAndMuteState()

        // Check if volume or mute state changed
        let volumeChanged = abs(newVolume - previousVolume) > 0.001  // Smaller threshold for more responsiveness
        let muteChanged = newMuted != previousMuteState

        if volumeChanged || muteChanged {
            logger.info("CHANGE: Volume updated: \(Int(newVolume * 100))%, Muted: \(newMuted)")

            // Update @Published properties and show HUD on main thread
            DispatchQueue.main.async {
                self.currentVolume = newVolume
                self.isMuted = newMuted
                self.hudController?.showVolumeHUD(volume: newVolume, isMuted: newMuted)
            }

            // Update previous values
            previousVolume = newVolume
            previousMuteState = newMuted
        }
    }

    // MARK: - System Event Monitoring

    private func startSystemEventMonitoring() {
        // Check if accessibility permissions are granted
        let accessibilityEnabled = AXIsProcessTrusted()

        if !accessibilityEnabled {
            logger.info(
                "Accessibility permissions not granted, so volume keys cannot be detected."
            )
            logger.info(
                "This means the HUD will not be displayed when pressing volume keys to go past min or max volume limits."
            )
            logger.info(
                "If you want this to work, please grant accessibility permissions in System Settings > Privacy & Security > Input Monitoring."
            )
            return
        }

        // Monitor system-defined events for volume key presses
        systemEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) {
            [weak self] event in
            self?.handleSystemDefinedEvent(event)
        }

        // Also monitor key events to catch volume keys that might not generate system-defined events
        keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) {
            _ in
        }

        logger.info("Started monitoring system-defined events for volume keys.")
        logger.info("Accessibility permissions: \(accessibilityEnabled ? "GRANTED" : "DENIED")")
    }

    private func stopSystemEventMonitoring() {
        if let monitor = systemEventMonitor {
            NSEvent.removeMonitor(monitor)
            systemEventMonitor = nil
            logger.info("Stopped monitoring system-defined events.")
        }
        if let keyMonitor = keyEventMonitor {
            NSEvent.removeMonitor(keyMonitor)
            keyEventMonitor = nil
        }
    }

    private func handleSystemDefinedEvent(_ event: NSEvent) {
        let currentTime = Date().timeIntervalSince1970

        // Track Caps Lock events
        if event.subtype.rawValue == 211 {
            lastCapsLockTime = currentTime
            logger.debug("Caps Lock event detected, ignoring volume events for 0.5 seconds.")
            return
        }

        // Volume keys generate NSSystemDefined events with subtype 8
        if event.subtype.rawValue == 8 {
            // Ignore volume events that happen within 0.5 seconds of Caps Lock
            if currentTime - lastCapsLockTime < 0.5 {
                logger.debug("Ignoring volume event, too close to Caps Lock.")
                return
            }

            let data1 = Int(event.data1)
            let keyCode = (data1 & 0xFFFF_0000) >> 16
            let keyFlags = data1 & 0x0000_FFFF
            let keyPressed = (keyFlags & 0xFF00) >> 8
            let keyState = (keyFlags & 0xFF00) >> 8  // 0x0A = keyDown, 0x0B = keyUp

            let isKeyDown = keyState == 0x0A
            guard isKeyDown else { return }

            // NX key codes: 0 = vol up, 1 = vol down, 7 = mute
            switch keyCode {
            case 1:  // Volume down
                logger.debug(
                    "Volume down (keyCode=\(keyCode), keyPressed=\(keyPressed))."
                )
                Task { @MainActor in
                    self.showHUDForVolumeKeyPress(isVolumeUp: false)
                }
            case 0:  // Volume up
                logger.debug(
                    "Volume up (keyCode=\(keyCode), keyPressed=\(keyPressed))."
                )
                Task { @MainActor in
                    self.showHUDForVolumeKeyPress(isVolumeUp: true)
                }
            default:
                break
            }
        }
    }

    @MainActor
    private func showHUDForVolumeKeyPress(isVolumeUp: Bool) {
        // Get current volume and mute state
        let (currentVol, currentMuted) = getCurrentVolumeAndMuteState()

        // Only show HUD on key presses if we're at volume boundaries (0% or 100%)
        // This prevents media keys from triggering the HUD when volume is between 1-99%
        let atMinVolume = currentVol <= 0.001
        let atMaxVolume = currentVol >= 0.999

        if !atMinVolume && !atMaxVolume {
            let currentTime = Date().timeIntervalSince1970
            // Debounce log messages as macOS seems to fire key events twice
            if currentTime - lastVolumeKeyLogTime > 0.1 {
                logger.debug(
                    "Key press detected while at \(Int(currentVol * 100))%, but will only trigger HUD at 0% or 100%."
                )
                lastVolumeKeyLogTime = currentTime
            }
            return
        }

        // Show HUD with current state
        hudController?.showVolumeHUD(volume: currentVol, isMuted: currentMuted)

        logger.debug(
            "Showing HUD for volume \(isVolumeUp ? "up" : "down") key press at boundary, current volume: \(Int(currentVol * 100))%, muted: \(currentMuted)"
        )
    }

    // MARK: - Default Device Monitoring

    private func startDefaultDeviceMonitoring() {
        guard !defaultDeviceListenerAdded else { return }

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            { (inObjectID, inNumberAddresses, inAddresses, inClientData) -> OSStatus in
                guard let clientData = inClientData else { return noErr }
                let volumeMonitor = Unmanaged<VolumeMonitor>.fromOpaque(clientData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    volumeMonitor.handleDefaultDeviceChanged()
                }
                return noErr
            },
            selfPtr
        )

        if status == noErr {
            defaultDeviceListenerAdded = true
            logger.info("Started monitoring default output device changes.")
        } else {
            logger.error("Failed to start monitoring default output device changes: \(status)")
        }
    }

    private func stopDefaultDeviceMonitoring() {
        guard defaultDeviceListenerAdded else { return }

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            { (inObjectID, inNumberAddresses, inAddresses, inClientData) -> OSStatus in
                return noErr
            },
            selfPtr
        )

        defaultDeviceListenerAdded = false
        logger.info("Stopped monitoring default output device changes.")
    }

    private func handleDefaultDeviceChanged() {
        logger.info("Default output device changed, re-registering volume listeners")

        // Remove old listeners
        removeVolumeListeners()

        // Get new default device
        var newDeviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &newDeviceID
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
        updateVolumeValuesOnStartup()

        logger.info("Successfully switched to new device: \(newDeviceID)")
    }

    private func removeVolumeListeners() {
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // Remove volume listener
        AudioObjectRemovePropertyListener(
            deviceID,
            &audioObjectPropertyAddress,
            { (inObjectID, inNumberAddresses, inAddresses, inClientData) -> OSStatus in
                return noErr
            },
            selfPtr
        )

        // Remove mute listener
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListener(
            deviceID,
            &muteAddress,
            { (inObjectID, inNumberAddresses, inAddresses, inClientData) -> OSStatus in
                return noErr
            },
            selfPtr
        )
    }

    private func addVolumeListeners() {
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // Register for volume change notifications
        AudioObjectAddPropertyListener(
            deviceID,
            &audioObjectPropertyAddress,
            { (inObjectID, inNumberAddresses, inAddresses, inClientData) -> OSStatus in
                guard let clientData = inClientData else { return noErr }
                let volumeMonitor = Unmanaged<VolumeMonitor>.fromOpaque(clientData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    volumeMonitor.updateVolumeValues()
                }
                return noErr
            },
            selfPtr
        )

        // Also monitor mute state
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListener(
            deviceID,
            &muteAddress,
            { (inObjectID, inNumberAddresses, inAddresses, inClientData) -> OSStatus in
                guard let clientData = inClientData else { return noErr }
                let volumeMonitor = Unmanaged<VolumeMonitor>.fromOpaque(clientData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    volumeMonitor.updateVolumeValues()
                }
                return noErr
            },
            selfPtr
        )
    }
}
