//
//  MediaKeyInterceptor.swift
//  by Danny Stewart (2025)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import AppKit
import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import PolyKit

/// Intercepts media key events at the HID level to suppress the system volume HUD.
/// When active, this class consumes volume key events before macOS sees them,
/// manually adjusts the volume, and triggers the custom HUD.
@MainActor
final class MediaKeyInterceptor {
    // MARK: Nested Types

    // MARK: Types

    private enum NXKeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    // MARK: Static Properties

    // MARK: Private - Event Handling

    /// Static callback for CGEvent tap. Bridges to instance method.
    private static let eventTapCallback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
        guard let userInfo else {
            return Unmanaged.passRetained(cgEvent)
        }

        let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

        // Handle tap disabled events
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Re-enable the tap
            if let tap = interceptor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(cgEvent)
        }

        // Only handle system-defined events
        guard type.rawValue == 14 else {
            return Unmanaged.passRetained(cgEvent)
        }

        // Process the event and determine if we should consume it
        return interceptor.handleEvent(cgEvent)
    }

    // MARK: Properties

    weak var hudController: HUDController?

    let logger: PolyLog = .init()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var audioPlayer: AVAudioPlayer?
    private var isRunning = false

    /// Standard volume step (1/16th, matching macOS default)
    private let standardStep: Float = 1.0 / 16.0

    /// Fine volume step when Option+Shift is held (1/64th)
    private let fineStep: Float = 1.0 / 64.0

    // MARK: Lifecycle

    init() {}

    deinit {
        // Note: stop() must be called before deinit since we're @MainActor
    }

    // MARK: Functions

    // MARK: Public Methods

    /// Start intercepting media key events.
    /// Returns true if the event tap was successfully created.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else {
            logger.debug("MediaKeyInterceptor already running.")
            return true
        }

        // Check accessibility permissions first
        guard AXIsProcessTrusted() else {
            logger.warning("MediaKeyInterceptor: Accessibility permissions not granted. Cannot intercept media keys.")
            return false
        }

        // Create the event tap
        // We use kCGHIDEventTap to intercept at the lowest level
        // and .defaultTap (not .listenOnly) so we can consume events
        let systemDefinedMask: CGEventMask = 1 << 14 // NX_SYSDEFINED = 14

        // We need to use a static callback that bridges to self
        // Store self in a context that the callback can access
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap, // Important: .defaultTap allows consuming events
                eventsOfInterest: systemDefinedMask,
                callback: MediaKeyInterceptor.eventTapCallback,
                userInfo: userInfo,
            ) else
        {
            logger.error("MediaKeyInterceptor: Failed to create CGEvent tap. Check accessibility permissions.")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isRunning = true
            logger.info("MediaKeyInterceptor: Started intercepting media keys.")
            return true
        } else {
            logger.error("MediaKeyInterceptor: Failed to create run loop source.")
            eventTap = nil
            return false
        }
    }

    /// Stop intercepting media key events.
    func stop() {
        guard isRunning else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        isRunning = false

        logger.info("MediaKeyInterceptor: Stopped intercepting media keys.")
    }

    /// Handle a system-defined CGEvent. Returns nil to consume the event,
    /// or the event to pass it through.
    private nonisolated func handleEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        // Convert to NSEvent to extract key info
        guard
            let nsEvent = NSEvent(cgEvent: cgEvent),
            nsEvent.type == .systemDefined,
            nsEvent.subtype.rawValue == 8 else
        {
            return Unmanaged.passRetained(cgEvent)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8

        // 0x0A = key down, 0x0B = key up
        // Only handle key down events
        guard keyState == 0x0A else {
            return Unmanaged.passRetained(cgEvent)
        }

        // Check if this is a volume key we want to intercept
        guard
            let keyType = NXKeyType(rawValue: keyCode),
            keyType == .soundUp || keyType == .soundDown || keyType == .mute else
        {
            // Not a volume key, pass through
            return Unmanaged.passRetained(cgEvent)
        }

        // Extract modifier flags for fine control detection
        let modifierFlags = nsEvent.modifierFlags
        let optionHeld = modifierFlags.contains(.option)
        let shiftHeld = modifierFlags.contains(.shift)
        let useFineStep = optionHeld && shiftHeld

        // Handle the key press on the main actor
        Task { @MainActor [weak self] in
            self?.handleVolumeKey(keyType: keyType, useFineStep: useFineStep)
        }

        // Consume the event by returning nil - this prevents the system HUD from appearing
        return nil
    }

    /// Handle a volume key press by adjusting volume and showing our HUD.
    private func handleVolumeKey(keyType: NXKeyType, useFineStep: Bool) {
        let step = useFineStep ? fineStep : standardStep

        switch keyType {
        case .soundUp:
            adjustVolume(delta: step)
            playFeedbackSoundIfEnabled()

        case .soundDown:
            adjustVolume(delta: -step)
            playFeedbackSoundIfEnabled()

        case .mute:
            toggleMute()

        default:
            break
        }
    }

    // MARK: Private - Volume Control

    /// Get the default output audio device ID.
    private func getDefaultOutputDevice() -> AudioDeviceID? {
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

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            logger.error("Failed to get default output device.")
            return nil
        }

        return deviceID
    }

    /// Get the current volume (0.0 to 1.0).
    private func getCurrentVolume(deviceID: AudioDeviceID) -> Float? {
        var volume: Float = 0.0
        var size = UInt32(MemoryLayout<Float>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &volume,
        )

        guard status == noErr else {
            logger.error("Failed to get current volume.")
            return nil
        }

        return volume
    }

    /// Set the volume (0.0 to 1.0).
    private func setVolume(_ volume: Float, deviceID: AudioDeviceID) {
        var newVolume = max(0.0, min(1.0, volume))
        let size = UInt32(MemoryLayout<Float>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &newVolume,
        )

        if status != noErr {
            logger.error("Failed to set volume: \(status)")
        }
    }

    /// Get the current mute state.
    private func getMuteState(deviceID: AudioDeviceID) -> Bool? {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &muted,
        )

        guard status == noErr else {
            return nil
        }

        return muted != 0
    }

    /// Set the mute state.
    private func setMuteState(_ muted: Bool, deviceID: AudioDeviceID) {
        var muteValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &muteValue,
        )

        if status != noErr {
            logger.error("Failed to set mute state: \(status)")
        }
    }

    /// Adjust volume by delta and show HUD.
    private func adjustVolume(delta: Float) {
        guard
            let deviceID = getDefaultOutputDevice(),
            let currentVolume = getCurrentVolume(deviceID: deviceID) else
        {
            return
        }

        // Calculate new volume with quantization to match step
        let steps = 1.0 / abs(delta)
        var newVolume = currentVolume + delta
        newVolume = round(newVolume * steps) / steps
        newVolume = max(0.0, min(1.0, newVolume))

        // If muted and adjusting volume, unmute first
        if let isMuted = getMuteState(deviceID: deviceID), isMuted, delta != 0 {
            setMuteState(false, deviceID: deviceID)
        }

        setVolume(newVolume, deviceID: deviceID)

        // Show our HUD
        let isMuted = getMuteState(deviceID: deviceID) ?? false
        hudController?.showVolumeHUD(volume: newVolume, isMuted: isMuted)

        logger.debug("Volume adjusted: \(Int(newVolume * 100))%")
    }

    /// Toggle mute state and show HUD.
    private func toggleMute() {
        guard
            let deviceID = getDefaultOutputDevice(),
            let isMuted = getMuteState(deviceID: deviceID),
            let currentVolume = getCurrentVolume(deviceID: deviceID) else
        {
            return
        }

        let newMuteState = !isMuted
        setMuteState(newMuteState, deviceID: deviceID)

        // Show our HUD
        hudController?.showVolumeHUD(volume: currentVolume, isMuted: newMuteState)

        logger.debug("Mute toggled: \(newMuteState)")
    }

    // MARK: Private - Feedback Sound

    /// Play the volume feedback sound if the user has it enabled in system preferences.
    private func playFeedbackSoundIfEnabled() {
        // Check if the user has feedback sounds enabled
        guard
            let globalDomain = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain"),
            let feedbackEnabled = globalDomain["com.apple.sound.beep.feedback"] as? Int,
            feedbackEnabled == 1 else
        {
            return
        }

        prepareAudioPlayerIfNeeded()

        guard let player = audioPlayer else { return }

        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    /// Prepare the audio player with the system volume sound.
    private func prepareAudioPlayerIfNeeded() {
        guard audioPlayer == nil else { return }

        let soundPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"

        guard FileManager.default.fileExists(atPath: soundPath) else {
            logger.warning("Volume feedback sound not found at: \(soundPath)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: soundPath))
            audioPlayer?.volume = 1.0
            audioPlayer?.numberOfLoops = 0
            audioPlayer?.prepareToPlay()
        } catch {
            logger.warning("Failed to load volume feedback sound: \(error.localizedDescription)")
        }
    }
}
