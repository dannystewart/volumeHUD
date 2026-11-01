//
//  ModernHUDView.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import SwiftUI

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
        .opacity(0.7)
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
