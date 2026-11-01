//
//  HUDStyle.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import SwiftUI

// MARK: - HUDStyle

enum HUDStyle: String {
    case classic
    case modern

    static let preferenceKey = "hudStyle"

    static var current: HUDStyle {
        HUDStyle(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .modern
    }

    var windowPadding: CGFloat { self == .modern ? 24 : 0 }
    var windowSize: CGFloat { 200 + windowPadding * 2 }
}

// MARK: - ModernHUDMetrics

/// Measured from the 3456 × 2234 fullscreen Xcode capture at 2× scale. Geometry is in screen
/// points; animation endpoints are estimates from the recording.
enum ModernHUDMetrics {
    static let size: CGFloat = 200
    static let cornerRadius: CGFloat = 26
    static let iconWidth: CGFloat = 96
    static let iconHeight: CGFloat = 90
    static let muteIconVerticalOffset: CGFloat = 3
    static let volumeIconFontSize: CGFloat = 88
    static let brightnessIconFontSize: CGFloat = 88
    static let iconCenterY: CGFloat = 82.9
    static let barsCenterY: CGFloat = 163.5
    static let transitionBlurRadius: CGFloat = 6
    static let entranceDuration: TimeInterval = 0.16
    static let exitDuration: TimeInterval = 0.13
}
