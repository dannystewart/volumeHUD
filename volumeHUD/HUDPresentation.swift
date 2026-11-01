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
            ZStack {
                // Preserve the layout while the native glass surface materializes.
                ModernHUDView(hudType: hudType, value: value, isMuted: isMuted)
                    .hidden()

                GlassEffectContainer {
                    ZStack {
                        if presentation.isPresented {
                            ModernHUDView(hudType: hudType, value: value, isMuted: isMuted)
                                // Blur foreground content before applying glass, not the native
                                // material or its reflective rim.
                                .transition(.modifier(
                                    active: HUDForegroundBlur(radius: reduceMotion ? 0 : ModernHUDMetrics.transitionBlurRadius),
                                    identity: HUDForegroundBlur(radius: 0),
                                ))
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: ModernHUDMetrics.cornerRadius, style: .continuous))
                                .glassEffectTransition(reduceMotion ? .identity : .materialize)
                        }
                    }
                }
            }
            .fixedSize()
            .environment(\.appearsActive, true)
            .padding(style.windowPadding)
        } else {
            HUDView(hudType: hudType, value: value, isMuted: isMuted, style: style)
        }
    }
}

// MARK: - HUDForegroundBlur

private struct HUDForegroundBlur: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
