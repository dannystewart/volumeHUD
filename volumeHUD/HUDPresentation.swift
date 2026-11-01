//
//  HUDPresentation.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import SwiftUI

// MARK: - HUDPresentation

@MainActor
@Observable
final class HUDPresentation {
    var isPresented = false
    var scale: CGFloat = ModernHUDMetrics.entranceScale
    var blurRadius: CGFloat = ModernHUDMetrics.transitionBlurRadius
}

// MARK: - HUDPresentationView

struct HUDPresentationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let hudType: HUDType
    let value: Float
    let isMuted: Bool
    let style: HUDStyle
    let presentation: HUDPresentation

    var body: some View {
        if style == .modern {
            GlassEffectContainer {
                ModernHUDView(hudType: hudType, value: value, isMuted: isMuted)
                    // Keep glass alive and blur only the foreground. Explicit
                    // presentation values replace materialization's fixed scale.
                    .blur(radius: reduceMotion ? 0 : presentation.blurRadius)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: ModernHUDMetrics.cornerRadius, style: .continuous))
                    .glassEffectTransition(.identity)
            }
            .fixedSize()
            // Transform the complete material container, not just its child:
            // foreground and glass must share the same center and coordinate space.
            .scaleEffect(reduceMotion ? 1 : presentation.scale, anchor: .center)
            .environment(\.appearsActive, true)
            .padding(style.windowPadding)
        } else {
            HUDView(hudType: hudType, value: value, isMuted: isMuted, style: style)
        }
    }
}
