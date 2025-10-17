//
//  PreviewHelpers.swift
//  by Danny Stewart (2025)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import Foundation

// Preview helpers for fast SwiftUI previews
//
// Usage in previews:
// - Pass `isPreviewMode: true` to monitors and controllers
// - Use mock managers for heavy services like LoginItemManager
// - This bypasses expensive initialization like framework loading, audio device queries, etc.

#if DEBUG
extension VolumeMonitor {
    /// Create a mock volume monitor for previews with sample data
    static func previewMock(volume: Float = 0.5, isMuted: Bool = false) -> VolumeMonitor {
        let monitor = VolumeMonitor(isPreviewMode: true)
        monitor.currentVolume = volume
        monitor.isMuted = isMuted
        return monitor
    }
}

extension BrightnessMonitor {
    /// Create a mock brightness monitor for previews with sample data
    static func previewMock(brightness: Float = 0.75) -> BrightnessMonitor {
        let monitor = BrightnessMonitor(isPreviewMode: true)
        monitor.currentBrightness = brightness
        return monitor
    }
}

extension HUDController {
    /// Create a mock HUD controller for previews
    static func previewMock() -> HUDController {
        HUDController(isPreviewMode: true)
    }
}
#endif
