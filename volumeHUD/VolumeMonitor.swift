//
//  VolumeMonitor.swift
//  volumeHUD
//
//  Created by Danny Stewart on 9/21/25.
//

import AVFoundation
import AudioToolbox
import Carbon
import Combine
import CoreAudio
import Foundation

class VolumeMonitor: ObservableObject, @unchecked Sendable {
    @Published var currentVolume: Float = 0.0
    @Published var isMuted: Bool = false

    private var audioObjectPropertyAddress: AudioObjectPropertyAddress
    private var isMonitoring = false
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var previousVolume: Float = 0.0
    private var previousMuteState: Bool = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyMonitoringEnabled: Bool = false

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

        // Start monitoring for volume key events
        startVolumeKeyMonitoring()

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

        // Stop volume key monitoring
        stopVolumeKeyMonitoring()

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

    // MARK: - Volume Key Monitoring

    /// Monitors for volume key presses even when volume is at min/max limits.
    /// This handles the case where pressing volume up at 100% or volume down at 0%
    /// doesn't trigger volume change events, but users still expect to see the HUD.

    private func startVolumeKeyMonitoring() {
        // Create event tap for volume keys
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let volumeMonitor = Unmanaged<VolumeMonitor>.fromOpaque(refcon)
                    .takeUnretainedValue()
                return volumeMonitor.handleVolumeKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            print(
                "Failed to create event tap for volume keys - accessibility permissions may not be granted"
            )
            print(
                "App will work for volume changes but won't show HUD for min/max cases"
            )
            isKeyMonitoringEnabled = false
            return
        }

        // Create run loop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource = runLoopSource else {
            print("Failed to create run loop source for volume key monitoring")
            isKeyMonitoringEnabled = false
            return
        }

        // Add to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        isKeyMonitoringEnabled = true
        print("Started monitoring volume key events")
    }

    private func stopVolumeKeyMonitoring() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isKeyMonitoringEnabled = false
        print("Stopped monitoring volume key events")
    }

    private func handleVolumeKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent)
        -> Unmanaged<CGEvent>?
    {
        // Only handle key down events and only if key monitoring is enabled
        guard type == .keyDown && isKeyMonitoringEnabled else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Check for volume up (key code 72) or volume down (key code 73)
        // These are the standard key codes for volume buttons on Mac keyboards
        if keyCode == 72 || keyCode == 73 {
            // Get current volume and mute state
            let (currentVol, currentMute) = getCurrentVolumeAndMuteState()

            // Show HUD with current volume level
            DispatchQueue.main.async {
                self.hudController?.showVolumeHUD(volume: currentVol, isMuted: currentMute)
            }

            print(
                "Volume key pressed (code: \(keyCode)) - showing HUD at \(Int(currentVol * 100))%")
        }

        return Unmanaged.passUnretained(event)
    }
}
