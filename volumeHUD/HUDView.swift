//
//  HUDView.swift
//  by Danny Stewart (2025)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import SwiftUI

// MARK: - HUDType

enum HUDType {
    case volume
    case brightness
}

// MARK: - HUDView

struct HUDView: View {
    // MARK: Properties

    let hudType: HUDType
    let value: Float
    let isMuted: Bool
    let isVisible: Bool

    private let hudSize: CGFloat = 200
    private let iconSize: CGFloat = 80

    // MARK: Computed Properties

    private var iconName: String {
        switch hudType {
        case .volume:
            if isMuted {
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

    // MARK: Content Properties

    var body: some View {
        VStack(spacing: 0) {
            VStack { // Icon section
                Spacer()
                    .frame(height: 56)
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    // SF Symbols has slight misalignment between speaker.slash.fill and speaker.fill
                    .offset(y: hudType == .volume && isMuted ? 2 : 0)
                Spacer()
            }
            .frame(height: 100)

            VStack { // Value bar section
                Spacer()
                    .frame(height: 40)
                HStack(spacing: 2) {
                    Spacer()
                        .frame(width: 20)
                    ForEach(0 ..< 16, id: \.self) { index in
                        Rectangle()
                            .fill(barColor(for: index))
                            .frame(width: 7.5, height: 7.5)
                    }
                    Spacer()
                        .frame(width: 20)
                }
            }
            .frame(height: 80)
        }
        .frame(width: hudSize, height: hudSize)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .environment(\.colorScheme, .dark),
        )
    }

    // MARK: Functions

    private func barColor(for index: Int) -> Color {
        if hudType == .volume, isMuted {
            return .white.opacity(0.2)
        }

        // Each of the 16 bars represents 1/16th of the total range
        // But we want to support 1/64th increments (4 sub-steps per bar)
        let barStart = Float(index) / 16.0
        let barEnd = Float(index + 1) / 16.0
        
        if value >= barEnd {
            // Fully illuminate this bar
            return .white.opacity(0.8)
        } else if value > barStart {
            // Partially illuminate this bar based on position within the bar
            // Each bar covers 1/16 (0.0625), divided into 4 quarters for 1/64 steps
            let positionInBar = (value - barStart) / (barEnd - barStart)
            
            // Quantize to 1/4 steps (0.25, 0.5, 0.75, 1.0)
            let quarterStep = round(positionInBar * 4.0) / 4.0
            
            // Map quarter steps to opacity levels between 0.2 (off) and 0.8 (on)
            // 0.25 -> 0.35, 0.5 -> 0.5, 0.75 -> 0.65, 1.0 -> 0.8
            let opacity = 0.2 + (quarterStep * 0.6)
            return .white.opacity(Double(opacity))
        } else {
            // Bar is below current value
            return .white.opacity(0.2)
        }
    }
}

#Preview("Volume") {
    ZStack {
        Color.black.frame(width: 360, height: 380).ignoresSafeArea()
        HUDView(hudType: .volume, value: 0.7, isMuted: false, isVisible: true)
    }
}

#Preview("Mute") {
    ZStack {
        Color.black.frame(width: 360, height: 380).ignoresSafeArea()
        HUDView(hudType: .volume, value: 0.0, isMuted: true, isVisible: true)
    }
}

#Preview("Brightness") {
    ZStack {
        Color.black.frame(width: 360, height: 380).ignoresSafeArea()
        HUDView(hudType: .brightness, value: 0.5, isMuted: false, isVisible: true)
    }
}
