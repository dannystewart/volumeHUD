//
//  HUDIconView.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import SwiftUI

// MARK: - HUDIconView

/// Shared symbol selection and optical alignment for both HUD styles.
struct HUDIconView: View {
    let hudType: HUDType
    let value: Float
    let isMuted: Bool
    var muteVerticalOffset: CGFloat = 2

    private var usesMuteSymbol: Bool {
        hudType == .volume && (isMuted || value <= 0.001)
    }

    private var iconName: String {
        switch hudType {
        case .volume:
            if usesMuteSymbol {
                "speaker.slash.fill"
            } else if value < 0.08 {
                "speaker.fill"
            } else if value < 0.33 {
                "speaker.wave.1.fill"
            } else if value < 0.66 {
                "speaker.wave.2.fill"
            } else {
                "speaker.wave.3.fill"
            }

        case .brightness:
            "sun.max"
        }
    }

    var body: some View {
        Image(systemName: iconName)
            // Default to Classic's original correction; other styles can tune it.
            .offset(y: usesMuteSymbol ? muteVerticalOffset : 0)
    }
}
