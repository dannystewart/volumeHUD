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
import IOKit.hid

class VolumeMonitor: ObservableObject, @unchecked Sendable {
    @Published var currentVolume: Float = 0.0
    @Published var isMuted: Bool = false

    private var audioObjectPropertyAddress: AudioObjectPropertyAddress
    private var isMonitoring = false
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var previousVolume: Float = 0.0
    private var previousMuteState: Bool = false
    private var systemEventMonitor: Any?
    private var hidManager: IOHIDManager?
    private var lastCapsLockTime: TimeInterval = 0

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
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

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

        // Start monitoring system-defined events for volume key presses
        startSystemEventMonitoring()

        // Also try IOHIDManager approach as fallback
        startHIDMonitoring()

        isMonitoring = true
        print("Started monitoring volume changes")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

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

        // Stop system event monitoring
        stopSystemEventMonitoring()

        // Stop HID monitoring
        stopHIDMonitoring()

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
                "Accessibility permissions not granted. Volume key detection at limits will not work."
            )
            print(
                "Please grant accessibility permissions in System Settings > Privacy & Security > Accessibility"
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
            // Only log volume-related key codes to avoid spam
            if event.keyCode == 27 || event.keyCode == 24 {  // Volume keys
                print(
                    "Volume key event: type=\(event.type.rawValue), keyCode=\(event.keyCode), modifierFlags=\(event.modifierFlags.rawValue)"
                )
            }
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

        // Debug: Log ALL system-defined events to catch Caps Lock
        print(
            "System-defined event: subtype=\(event.subtype.rawValue), data1=\(String(format: "0x%08X", event.data1))"
        )

        // Volume keys generate NSSystemDefined events with subtype 8
        if event.subtype.rawValue == 8 {
            // Ignore volume events that happen within 0.5 seconds of Caps Lock
            if currentTime - lastCapsLockTime < 0.5 {
                print("Ignoring volume event, too close to Caps Lock")
                return
            }
            let keyCode = Int((event.data1 & 0xFFFF_0000) >> 16)
            let keyFlags = Int(event.data1 & 0x0000_FFFF)
            let keyPressed = (keyFlags & 0xFF00) >> 8

            print(
                "Volume key event: keyCode=\(keyCode), keyFlags=\(String(format: "0x%04X", keyFlags)), keyPressed=\(keyPressed)"
            )

            // Handle volume key events - check the keyPressed value (which contains the actual key info)
            switch keyPressed {
            case 10:  // Volume down key (0x0A)
                print("✅ Volume down key detected (at limit detection) - keyPressed=\(keyPressed)")
                Task { @MainActor in
                    self.showHUDForVolumeKeyPress(isVolumeUp: false)
                }
            case 11:  // Volume up key (0x0B)
                print("✅ Volume up key detected (at limit detection) - keyPressed=\(keyPressed)")
                Task { @MainActor in
                    self.showHUDForVolumeKeyPress(isVolumeUp: true)
                }
            default:
                // Only log if it's not a volume key to avoid spam
                if keyPressed != 0 {
                    print(
                        "⚠️ Non-volume system event - keyPressed=\(keyPressed), keyCode=\(keyCode)")
                }
                break
            }
        }
    }

    @MainActor
    private func showHUDForVolumeKeyPress(isVolumeUp: Bool) {
        // Get current volume and mute state
        let (currentVol, currentMuted) = getCurrentVolumeAndMuteState()

        // Show HUD with current state
        hudController?.showVolumeHUD(volume: currentVol, isMuted: currentMuted)

        print(
            "Showing HUD for volume key press: \(isVolumeUp ? "up" : "down"), current volume: \(Int(currentVol * 100))%, muted: \(currentMuted)"
        )
    }

    // MARK: - HID Monitoring (Alternative Approach)

    private func startHIDMonitoring() {
        print("Starting HID monitoring for volume keys...")

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            print("Failed to create HID manager")
            return
        }

        // Set up matching criteria for consumer devices (volume keys)
        let matchingDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_Consumer,
            kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl,
        ]

        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        // Set up input value callback
        let callback: IOHIDValueCallback = { context, result, sender, value in
            guard let context = context else { return }
            let volumeMonitor = Unmanaged<VolumeMonitor>.fromOpaque(context).takeUnretainedValue()
            volumeMonitor.handleHIDValue(value)
        }

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(manager, callback, selfPtr)

        // Open the manager
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            print("Failed to open HID manager: \(openResult)")
            return
        }

        // Schedule with run loop
        IOHIDManagerScheduleWithRunLoop(
            manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        print("HID monitoring started successfully")
    }

    private func stopHIDMonitoring() {
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(
                manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
            print("HID monitoring stopped")
        }
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usage = IOHIDElementGetUsage(element)
        let usagePage = IOHIDElementGetUsagePage(element)

        print("HID event: usagePage=\(usagePage), usage=\(usage)")

        // Check for volume keys in consumer usage page
        if usagePage == kHIDPage_Consumer {
            switch usage {
            case UInt32(kHIDUsage_Csmr_VolumeIncrement):
                print("Volume UP key detected via HID")
                Task { @MainActor in
                    self.showHUDForVolumeKeyPress(isVolumeUp: true)
                }
            case UInt32(kHIDUsage_Csmr_VolumeDecrement):
                print("Volume DOWN key detected via HID")
                Task { @MainActor in
                    self.showHUDForVolumeKeyPress(isVolumeUp: false)
                }
            default:
                break
            }
        }
    }
}
