//
//  VolumeMonitor.swift
//  volumeHUD
//
//  Created by Danny Stewart on 9/21/25.
//

import AVFoundation
import AudioToolbox
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
        updateVolumeValuesSilently()

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

        isMonitoring = false
        print("Stopped monitoring volume changes")
    }

    private func updateVolumeValuesSilently() {
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

        if volumeStatus == noErr {
            // Quantize volume to 16 steps to match the volume bars
            let quantizedVolume = round(volume * 16.0) / 16.0
            currentVolume = quantizedVolume
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

        if muteStatus == noErr {
            isMuted = muted != 0
        }

        // Set previous values to current values to prevent initial HUD display
        previousVolume = currentVolume
        previousMuteState = isMuted

        print("Initial volume set: \(Int(currentVolume * 100))%, Muted: \(isMuted)")
    }

    private func updateVolumeValues() {
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
        var newMuted: Bool = isMuted

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

        if muteStatus == noErr {
            newMuted = muted != 0
        }

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
}
