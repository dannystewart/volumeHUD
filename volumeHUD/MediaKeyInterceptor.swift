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
import CoreGraphics
import Foundation
import IOKit
import PolyKit

/// Intercepts media key events at the HID level to suppress the system HUDs.
/// When active, this class consumes volume/brightness key events before macOS sees them,
/// manually adjusts the values, and triggers the custom HUD.
///
/// Features intelligent fallback: if adjusting a value fails (e.g., brightness on external display),
/// interception for that type is automatically disabled and events pass through to the system.
@MainActor
final class MediaKeyInterceptor {
    // MARK: Nested Types

    private enum NXKeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    // MARK: Static Properties

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

    /// Whether volume interception is currently working (resets on app restart).
    /// Using nonisolated(unsafe) is acceptable here because:
    /// - The flag only transitions from true to false (never back)
    /// - A race condition would only allow one extra event through, which is acceptable
    private nonisolated(unsafe) var volumeInterceptionWorking = true

    /// Whether brightness interception is currently working (resets on app restart).
    /// Using nonisolated(unsafe) for the same reasons as volumeInterceptionWorking.
    private nonisolated(unsafe) var brightnessInterceptionWorking = true

    /// Standard step (1/16th, matching macOS default)
    private let standardStep: Float = 1.0 / 16.0

    /// Fine step when Option+Shift is held (1/64th)
    private let fineStep: Float = 1.0 / 64.0

    // MARK: DisplayServices

    private var displayServicesHandle: UnsafeMutableRawPointer?
    private var canChangeBrightnessFunc: (@convention(c) (CGDirectDisplayID) -> Bool)?
    private var getBrightnessFunc: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> kern_return_t)?
    private var setBrightnessFunc: (@convention(c) (CGDirectDisplayID, Float) -> kern_return_t)?

    // MARK: Computed Properties

    /// Whether brightness HUD feature is enabled in settings
    private var brightnessHUDEnabled: Bool {
        UserDefaults.standard.bool(forKey: "brightnessEnabled")
    }

    // MARK: Lifecycle

    init() {
        loadDisplayServices()
    }

    deinit {
        // Note: stop() must be called before deinit since we're @MainActor
        // DisplayServices handle is closed in stop()
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

        // Reset fallback states on start (allows re-testing each app launch)
        volumeInterceptionWorking = true
        brightnessInterceptionWorking = true

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

        // Close DisplayServices handle
        if let handle = displayServicesHandle {
            dlclose(handle)
            displayServicesHandle = nil
        }

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

        guard let keyType = NXKeyType(rawValue: keyCode) else {
            return Unmanaged.passRetained(cgEvent)
        }

        // Extract modifier flags for fine control detection
        let modifierFlags = nsEvent.modifierFlags
        let optionHeld = modifierFlags.contains(.option)
        let shiftHeld = modifierFlags.contains(.shift)
        let useFineStep = optionHeld && shiftHeld

        // Check if this is a key we want to intercept
        switch keyType {
        case .soundUp, .soundDown, .mute:
            // Check if volume interception is still working
            guard volumeInterceptionWorking else {
                return Unmanaged.passRetained(cgEvent) // Pass through to system
            }

            // Handle the key press on the main actor
            Task { @MainActor [weak self] in
                self?.handleVolumeKey(keyType: keyType, useFineStep: useFineStep)
            }

            // Consume the event
            return nil

        case .brightnessUp, .brightnessDown:
            // Only intercept brightness if the brightness HUD feature is enabled
            // and brightness interception is still working
            guard brightnessInterceptionWorking else {
                return Unmanaged.passRetained(cgEvent) // Pass through to system
            }

            // Handle the key press on the main actor
            Task { @MainActor [weak self] in
                self?.handleBrightnessKey(keyType: keyType, useFineStep: useFineStep)
            }

            // Consume the event
            return nil
        }
    }

    // MARK: Private - Key Handlers

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

    /// Handle a brightness key press by adjusting brightness and showing our HUD.
    private func handleBrightnessKey(keyType: NXKeyType, useFineStep: Bool) {
        let step = useFineStep ? fineStep : standardStep

        switch keyType {
        case .brightnessUp:
            adjustBrightness(delta: step)

        case .brightnessDown:
            adjustBrightness(delta: -step)

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
            return nil
        }

        return volume
    }

    /// Set the volume (0.0 to 1.0). Returns the actual volume after setting.
    @discardableResult
    private func setVolume(_ volume: Float, deviceID: AudioDeviceID) -> Float? {
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

        guard status == noErr else {
            return nil
        }

        return getCurrentVolume(deviceID: deviceID)
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
    private func setMuteState(_ muted: Bool, deviceID: AudioDeviceID) -> Bool {
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

        return status == noErr
    }

    /// Adjust volume by delta and show HUD. Verifies the change worked.
    private func adjustVolume(delta: Float) {
        guard let deviceID = getDefaultOutputDevice() else {
            disableVolumeInterception(reason: "cannot get audio device")
            return
        }

        guard let currentVolume = getCurrentVolume(deviceID: deviceID) else {
            disableVolumeInterception(reason: "cannot read volume")
            return
        }

        // Calculate expected new volume with quantization
        let steps = 1.0 / abs(delta)
        var expectedVolume = currentVolume + delta
        expectedVolume = round(expectedVolume * steps) / steps
        expectedVolume = max(0.0, min(1.0, expectedVolume))

        // Check if we're at a boundary (where change isn't expected)
        let atBoundary = (currentVolume <= 0.001 && delta < 0) || (currentVolume >= 0.999 && delta > 0)

        // If muted and adjusting volume, unmute first
        if let isMuted = getMuteState(deviceID: deviceID), isMuted, delta != 0 {
            _ = setMuteState(false, deviceID: deviceID)
        }

        // Set the volume and get the actual result
        guard let actualVolume = setVolume(expectedVolume, deviceID: deviceID) else {
            disableVolumeInterception(reason: "cannot set volume")
            return
        }

        // Verify the change worked (if not at a boundary)
        if !atBoundary {
            let volumeChanged = abs(actualVolume - currentVolume) > 0.001
            if !volumeChanged {
                disableVolumeInterception(reason: "volume change did not take effect")
                // Still show HUD with current state even though we're disabling
            }
        }

        // Show our HUD
        let isMuted = getMuteState(deviceID: deviceID) ?? false
        hudController?.showVolumeHUD(volume: actualVolume, isMuted: isMuted)

        logger.debug("Volume adjusted: \(Int(actualVolume * 100))%")
    }

    /// Toggle mute state and show HUD.
    private func toggleMute() {
        guard let deviceID = getDefaultOutputDevice() else {
            disableVolumeInterception(reason: "cannot get audio device")
            return
        }

        guard let isMuted = getMuteState(deviceID: deviceID) else {
            disableVolumeInterception(reason: "cannot read mute state")
            return
        }

        guard let currentVolume = getCurrentVolume(deviceID: deviceID) else {
            disableVolumeInterception(reason: "cannot read volume")
            return
        }

        let newMuteState = !isMuted
        guard setMuteState(newMuteState, deviceID: deviceID) else {
            disableVolumeInterception(reason: "cannot set mute state")
            return
        }

        // Show our HUD
        hudController?.showVolumeHUD(volume: currentVolume, isMuted: newMuteState)

        logger.debug("Mute toggled: \(newMuteState)")
    }

    /// Disable volume interception and log the reason.
    private func disableVolumeInterception(reason: String) {
        guard volumeInterceptionWorking else { return } // Already disabled
        volumeInterceptionWorking = false
        logger.warning("Volume key interception disabled: \(reason). Future volume keys will pass through to system.")
    }

    // MARK: Private - Brightness Control

    /// Load the DisplayServices framework for brightness control.
    private func loadDisplayServices() {
        guard
            let handle = dlopen(
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                RTLD_LAZY,
            ) else
        {
            logger.debug("DisplayServices framework not available for brightness control.")
            return
        }

        guard
            let canChangeBrightnessPtr = dlsym(handle, "DisplayServicesCanChangeBrightness"),
            let getBrightnessPtr = dlsym(handle, "DisplayServicesGetBrightness"),
            let setBrightnessPtr = dlsym(handle, "DisplayServicesSetBrightness") else
        {
            dlclose(handle)
            logger.debug("DisplayServices brightness functions not available.")
            return
        }

        displayServicesHandle = handle
        canChangeBrightnessFunc = unsafeBitCast(
            canChangeBrightnessPtr,
            to: (@convention(c) (CGDirectDisplayID) -> Bool).self,
        )
        getBrightnessFunc = unsafeBitCast(
            getBrightnessPtr,
            to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> kern_return_t).self,
        )
        setBrightnessFunc = unsafeBitCast(
            setBrightnessPtr,
            to: (@convention(c) (CGDirectDisplayID, Float) -> kern_return_t).self,
        )

        logger.debug("DisplayServices framework loaded for brightness control.")
    }

    /// Get the built-in display ID.
    private func getBuiltinDisplayID() -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        if result != .success || displayCount == 0 {
            return nil
        }

        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        result = CGGetActiveDisplayList(displayCount, &activeDisplays, &displayCount)
        if result != .success {
            return nil
        }

        for display in activeDisplays.prefix(Int(displayCount)) {
            if CGDisplayIsBuiltin(display) != 0 {
                return display
            }
        }

        return nil
    }

    /// Get the current brightness (0.0 to 1.0).
    private func getCurrentBrightness(displayID: CGDirectDisplayID) -> Float? {
        guard let getBrightness = getBrightnessFunc else {
            return nil
        }

        var brightness: Float = 0.0
        let result = getBrightness(displayID, &brightness)

        guard result == KERN_SUCCESS else {
            return nil
        }

        return brightness
    }

    /// Set the brightness (0.0 to 1.0). Returns the actual brightness after setting.
    @discardableResult
    private func setBrightness(_ brightness: Float, displayID: CGDirectDisplayID) -> Float? {
        guard let setBrightness = setBrightnessFunc else {
            return nil
        }

        let clampedBrightness = max(0.0, min(1.0, brightness))
        let result = setBrightness(displayID, clampedBrightness)

        guard result == KERN_SUCCESS else {
            return nil
        }

        return getCurrentBrightness(displayID: displayID)
    }

    /// Check if brightness can be changed on a display.
    private func canChangeBrightness(displayID: CGDirectDisplayID) -> Bool {
        guard let canChange = canChangeBrightnessFunc else {
            return false
        }
        return canChange(displayID)
    }

    /// Adjust brightness by delta and show HUD. Verifies the change worked.
    private func adjustBrightness(delta: Float) {
        // Check if DisplayServices is available
        guard setBrightnessFunc != nil else {
            disableBrightnessInterception(reason: "DisplayServices not available")
            return
        }

        // Get built-in display
        guard let displayID = getBuiltinDisplayID() else {
            disableBrightnessInterception(reason: "no built-in display found")
            return
        }

        // Check if brightness can be changed
        guard canChangeBrightness(displayID: displayID) else {
            disableBrightnessInterception(reason: "display does not support brightness control")
            return
        }

        guard let currentBrightness = getCurrentBrightness(displayID: displayID) else {
            disableBrightnessInterception(reason: "cannot read brightness")
            return
        }

        // Calculate expected new brightness with quantization
        let steps = 1.0 / abs(delta)
        var expectedBrightness = currentBrightness + delta
        expectedBrightness = round(expectedBrightness * steps) / steps
        expectedBrightness = max(0.0, min(1.0, expectedBrightness))

        // Check if we're at a boundary
        let atBoundary = (currentBrightness <= 0.001 && delta < 0) || (currentBrightness >= 0.999 && delta > 0)

        // Set the brightness and get the actual result
        guard let actualBrightness = setBrightness(expectedBrightness, displayID: displayID) else {
            disableBrightnessInterception(reason: "cannot set brightness")
            return
        }

        // Verify the change worked (if not at a boundary)
        if !atBoundary {
            let brightnessChanged = abs(actualBrightness - currentBrightness) > 0.001
            if !brightnessChanged {
                disableBrightnessInterception(reason: "brightness change did not take effect")
                // Still show HUD with current state even though we're disabling
            }
        }

        // Quantize for display
        let quantizedBrightness = round(actualBrightness * 16.0) / 16.0

        // Show our HUD (only if brightness feature is enabled)
        if brightnessHUDEnabled {
            hudController?.showBrightnessHUD(brightness: quantizedBrightness)
        }

        logger.debug("Brightness adjusted: \(Int(quantizedBrightness * 100))%")
    }

    /// Disable brightness interception and log the reason.
    private func disableBrightnessInterception(reason: String) {
        guard brightnessInterceptionWorking else { return } // Already disabled
        brightnessInterceptionWorking = false
        logger.warning("Brightness key interception disabled: \(reason). Future brightness keys will pass through to system.")
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
