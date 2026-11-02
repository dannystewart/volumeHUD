//
//  ModernHUD.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import AppKit
import SwiftUI

// MARK: - ModernHUDMetrics

/// Measured from the 3456 × 2234 fullscreen Xcode capture at 2× scale. Geometry is in screen
/// points; animation endpoints are estimates from the recording.
enum ModernHUDMetrics {
    static let size: CGFloat = 200
    static let cornerRadius: CGFloat = 26
    static let iconWidth: CGFloat = 96
    static let iconHeight: CGFloat = 90
    static let muteIconVerticalOffset: CGFloat = 3
    static let volumeIconFontSize: CGFloat = 86
    static let brightnessIconFontSize: CGFloat = 86
    static let iconCenterY: CGFloat = 83
    static let barsCenterY: CGFloat = 165
    static let transitionBlurRadius: CGFloat = 5
    static let entranceScale: CGFloat = 0.97
    static let exitScale: CGFloat = 0.97
    static let entranceDuration: TimeInterval = 0.06
    static let exitDuration: TimeInterval = 0.13
}

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

// MARK: - ModernHUDView

struct ModernHUDView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let hudType: HUDType
    let value: Float
    let isMuted: Bool

    private var foregroundColor: Color {
        let appearanceName: NSAppearance.Name = switch (colorScheme, colorSchemeContrast) {
        case (.dark, .increased): .accessibilityHighContrastDarkAqua
        case (.dark, _): .darkAqua
        case (_, .increased): .accessibilityHighContrastAqua
        default: .aqua
        }
        var resolvedColor = NSColor.white
        NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
            resolvedColor = NSColor.labelColor.usingColorSpace(.sRGB) ?? .white
        }
        // Resolve the system semantic color to components, rather than passing a hierarchical style
        // into glass. Both symbols and shapes then use exactly the same paint, including while the
        // glass surface is being removed.
        return Color(
            .sRGB,
            red: resolvedColor.redComponent,
            green: resolvedColor.greenComponent,
            blue: resolvedColor.blueComponent,
            opacity: resolvedColor.alphaComponent,
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HUDIconView(hudType: hudType, value: value, isMuted: isMuted, muteVerticalOffset: ModernHUDMetrics.muteIconVerticalOffset)
                .font(.system(size: hudType == .volume ? ModernHUDMetrics.volumeIconFontSize : ModernHUDMetrics.brightnessIconFontSize, weight: .regular))
                .foregroundStyle(foregroundColor)
                .frame(width: ModernHUDMetrics.iconWidth, height: ModernHUDMetrics.iconHeight)
                .position(x: ModernHUDMetrics.size / 2, y: ModernHUDMetrics.iconCenterY)

            ModernHUDValueBars(value: value, isMuted: hudType == .volume && isMuted, foregroundColor: foregroundColor)
                .position(x: ModernHUDMetrics.size / 2, y: ModernHUDMetrics.barsCenterY)
        }
        .frame(width: ModernHUDMetrics.size, height: ModernHUDMetrics.size)
        .opacity(0.72)
        .environment(\.appearsActive, true)
    }
}

// MARK: - ModernHUDValueBars

private struct ModernHUDValueBars: View {
    let value: Float
    let isMuted: Bool
    let foregroundColor: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< 16, id: \.self) { index in
                let fraction = isMuted ? 0 : (min(max(value * 16 - Float(index), 0), 1) * 4).rounded() / 4
                // Partition the segment instead of painting translucent fill over a dim track,
                // which would make bars brighter than the icon.
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(foregroundColor)
                        .frame(width: 7.5 * CGFloat(fraction))
                    Rectangle()
                        .fill(foregroundColor.opacity(0.25))
                        .frame(width: 7.5 * CGFloat(1 - fraction))
                }
                .frame(width: 7.5, height: 7.5)
            }
        }
        .fixedSize()
    }
}

#Preview("Modern Volume") {
    GlassEffectContainer {
        ModernHUDView(hudType: .volume, value: 0.7, isMuted: false)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: ModernHUDMetrics.cornerRadius, style: .continuous))
    }
    .padding(24)
}

#Preview("Modern Brightness") {
    GlassEffectContainer {
        ModernHUDView(hudType: .brightness, value: 0.5, isMuted: false)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: ModernHUDMetrics.cornerRadius, style: .continuous))
    }
    .padding(24)
}
