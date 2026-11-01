//
//  ModernHUDPanel.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import AppKit

// MARK: - ModernHUDPanel

/// A nonactivating overlay that renders glass as active without taking key focus.
@MainActor
final class ModernHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Xcode's DVTBezelAlertPanel returns YES from this private window hook. SwiftUI's
    /// appearsActive value does not replace it: AppKit's glass renderer still uses the window's
    /// native active-appearance state. Both targets preserve the same glass appearance.
    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    func hasActiveGlassAppearanceIgnoringKeyFocus() -> Bool { true }
}
