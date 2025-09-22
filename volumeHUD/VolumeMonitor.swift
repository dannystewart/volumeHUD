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

class VolumeMonitor: ObservableObject, @unchecked Sendable {
    @Published var currentVolume: Float = 0.0
    @Published var isMuted: Bool = false

    private var audioObjectPropertyAddress: AudioObjectPropertyAddress
    private var isMonitoring = false
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var previousVolume: Float = 0.0
    private var previousMuteState: Bool = false
    private var systemEventMonitor: Any?
    private var lastCapsLockTime: TimeInterval = 0
    private var defaultDeviceListenerAdded = false

    weak var hudController: HUDController?

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
            print("Failed to get default output device")
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
        print("Started monitoring volume changes")
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
        print("Stopped monitoring volume changes")
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

        print("Initial volume set: \(Int(newVolume * 100))%, Muted: \(newMuted)")
    }

    private func updateVolumeValues() {
        let (newVolume, newMuted) = getCurrentVolumeAndMuteState()

        // Check if volume or mute state changed
        let volumeChanged = abs(newVolume - previousVolume) > 0.001  // Smaller threshold for more responsiveness
        let muteChanged = newMuted != previousMuteState

        if volumeChanged || muteChanged {
            print("Volume updated: \(Int(newVolume * 100))%, Muted: \(newMuted)")

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
            print(
                "Accessibility permissions not granted, so volume keys cannot be detected."
            )
            print(
                "This means the HUD will not be displayed when pressing volume keys to go past min or max volume limits."
            )
            print(
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
        let keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) {
            event in
        }

        // Store both monitors for cleanup
        if systemEventMonitor == nil {
            systemEventMonitor = keyEventMonitor
        }

        print("Started monitoring system-defined events for volume keys")
        print("Accessibility permissions: \(accessibilityEnabled ? "GRANTED" : "DENIED")")
    }

    private func stopSystemEventMonitoring() {
        if let monitor = systemEventMonitor {
            NSEvent.removeMonitor(monitor)
            systemEventMonitor = nil
            print("Stopped monitoring system-defined events")
        }
    }

    private func handleSystemDefinedEvent(_ event: NSEvent) {
        let currentTime = Date().timeIntervalSince1970

        // Track Caps Lock events
        if event.subtype.rawValue == 211 {
            lastCapsLockTime = currentTime
            print("Caps Lock event detected, ignoring volume events for 0.5 seconds")
            return
        }

        // Volume keys generate NSSystemDefined events with subtype 8
        if event.subtype.rawValue == 8 {
            // Ignore volume events that happen within 0.5 seconds of Caps Lock
            if currentTime - lastCapsLockTime < 0.5 {
                print("Ignoring volume event, too close to Caps Lock")
                return
            }
            let keyFlags = Int(event.data1 & 0x0000_FFFF)
            let keyPressed = (keyFlags & 0xFF00) >> 8

            // Handle volume key events
            switch keyPressed {
            case 10:  // Volume down key (0x0A)
                print("Volume key detected while at limit boundary - keyPressed=\(keyPressed)")
                Task { @MainActor in
                    self.showHUDForVolumeKeyPress(isVolumeUp: false)
                }
            case 11:  // Volume up key (0x0B)
                print("Volume key detected while at limit boundary - keyPressed=\(keyPressed)")
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
            print(
                "Volume key press detected but volume is \(Int(currentVol * 100))% (volume change detection will handle it)"
            )
            return
        }

        // Show HUD with current state
        hudController?.showVolumeHUD(volume: currentVol, isMuted: currentMuted)

        print(
            "Showing HUD for volume key press at boundary: \(isVolumeUp ? "up" : "down"), current volume: \(Int(currentVol * 100))%, muted: \(currentMuted)"
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
            print("Started monitoring default output device changes")
        } else {
            print("Failed to start monitoring default output device changes: \(status)")
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
        print("Stopped monitoring default output device changes")
    }

    private func handleDefaultDeviceChanged() {
        print("Default output device changed, re-registering volume listeners")

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
            print("Failed to get new default output device")
            return
        }

        // Update device ID
        deviceID = newDeviceID

        // Add new listeners
        addVolumeListeners()

        // Update volume values for the new device
        updateVolumeValuesOnStartup()

        print("Successfully switched to new device: \(newDeviceID)")
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
