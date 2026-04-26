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
    let hudType: HUDType
    let value: Float
    let isMuted: Bool

    private let hudSize: CGFloat = 200
    private let iconSize: CGFloat = 80

    private var iconName: String {
        switch hudType {
        case .volume:
            if isMuted || value <= 0.001 {
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
        VStack(spacing: 0) {
            VStack { // Icon section
                Spacer()
                    .frame(height: 56)
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    // SF Symbols has misalignment between speaker.slash.fill and speaker.fill
                    .offset(y: hudType == .volume && (isMuted || value <= 0.001) ? 2 : 0)
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
                        barView(for: index)
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
                .fill(.regularMaterial),
        )
    }

    @ViewBuilder
    private func barView(for index: Int) -> some View {
        let barWidth: CGFloat = 7.5
        let barHeight: CGFloat = 7.5

        if hudType == .volume, isMuted {
            // Show all bars dimmed when muted
            Rectangle()
                .fill(.primary.opacity(0.2))
                .frame(width: barWidth, height: barHeight)
        } else {
            // Each of the 16 bars represents 1/16th of the total range. Support 1/64th increments
            // by filling each bar horizontally in quarters.
            let barStart = Float(index) / 16.0
            let barEnd = Float(index + 1) / 16.0

            if value >= barEnd {
                // Fully filled bar
                Rectangle()
                    .fill(.primary.opacity(0.7))
                    .frame(width: barWidth, height: barHeight)
            } else if value > barStart {
                // Partially filled bar - calculate fill percentage
                let positionInBar = (value - barStart) / (barEnd - barStart)

                // Quantize to 1/4 steps (0.25, 0.5, 0.75)
                let quarterStep = round(positionInBar * 4.0) / 4.0
                let fillWidth = barWidth * CGFloat(quarterStep)

                // Show partial fill with overlay
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.primary.opacity(0.2))
                        .frame(width: barWidth, height: barHeight)

                    Rectangle()
                        .fill(.primary.opacity(0.7))
                        .frame(width: fillWidth, height: barHeight)
                }
                .frame(width: barWidth, height: barHeight)
            } else {
                // Empty bar
                Rectangle()
                    .fill(.primary.opacity(0.2))
                    .frame(width: barWidth, height: barHeight)
            }
        }
    }
}

#Preview("Volume") {
    ZStack {
        Color.black.frame(width: 360, height: 380).ignoresSafeArea()
        HUDView(hudType: .volume, value: 0.7, isMuted: false)
    }
}

#Preview("Mute") {
    ZStack {
        Color.black.frame(width: 360, height: 380).ignoresSafeArea()
        HUDView(hudType: .volume, value: 0.0, isMuted: true)
    }
}

#Preview("Brightness") {
    ZStack {
        Color.black.frame(width: 360, height: 380).ignoresSafeArea()
        HUDView(hudType: .brightness, value: 0.5, isMuted: false)
    }
}
