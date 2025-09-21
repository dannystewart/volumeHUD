//
//  VolumeHUDView.swift
//  volumeHUD
//
//  Created by Danny Stewart on 9/21/25.
//

import SwiftUI

struct VolumeHUDView: View {
    let volume: Float
    let isMuted: Bool
    let isVisible: Bool

    private let hudSize: CGFloat = 200
    private let iconSize: CGFloat = 80

    var body: some View {
        VStack(spacing: 0) {
            VStack {  // Volume icon section
                Spacer()
                    .frame(height: 56)
                Image(systemName: volumeIcon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .offset(y: isMuted ? 2 : 0)  // Align the mute icon with regular volume icons
                Spacer()
            }
            .frame(height: 100)

            VStack {  // Volume bar section
                Spacer()
                    .frame(height: 40)  // Add space to move the volume bars down a bit
                HStack(spacing: 2) {
                    Spacer()
                        .frame(width: 20)  // Left margin (to center)
                    ForEach(0..<16, id: \.self) { index in
                        Rectangle()  // Actual volume bars
                            .fill(volumeBarColor(for: index))
                            .frame(width: 7.5, height: 7.5)
                    }
                    Spacer()
                        .frame(width: 20)  // Right margin (to center)
                }
            }
            .frame(height: 80)
        }
        .frame(width: hudSize, height: hudSize)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .environment(\.colorScheme, .dark)
        )
        .opacity(isVisible ? 1.0 : 0.0)
    }

    private var volumeIcon: String {
        if isMuted {
            return "speaker.slash.fill"
        } else if volume < 0.25 {
            return "speaker.fill"
        } else if volume < 0.5 {
            return "speaker.wave.1.fill"
        } else if volume < 0.75 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private func volumeBarColor(for index: Int) -> Color {
        if isMuted {
            return .white.opacity(0.2)  // All bars dimmed when muted
        }
        let threshold = Float(index) / 16.0
        if volume > threshold {
            return .white.opacity(0.8)  // Active bars are lighter
        } else {
            return .white.opacity(0.2)  // Inactive bars are dimmed
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VolumeHUDView(volume: 0.7, isMuted: false, isVisible: true)
    }
}

#Preview("Muted") {
    ZStack {
        Color.black.ignoresSafeArea()
        VolumeHUDView(volume: 0.0, isMuted: true, isVisible: true)
    }
}
