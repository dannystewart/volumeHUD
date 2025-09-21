//
//  VolumeHUDView.swift
//  Volume HUD
//
//  Created by Danny Stewart on 9/21/25.
//

import SwiftUI

struct VolumeHUDView: View {
    let volume: Float
    let isMuted: Bool
    let isVisible: Bool

    private let hudSize: CGFloat = 200
    private let iconSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            // Volume icon - centered in upper portion
            VStack {
                Spacer()
                Image(systemName: volumeIcon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(height: 120)

            // Volume bars or mute indicator - fixed lower area
            VStack {
                if !isMuted {
                    HStack(spacing: 3) {
                        Spacer()
                            .frame(width: 20)
                        ForEach(0..<16, id: \.self) { index in
                            // Volume bars
                            Rectangle()
                                .fill(volumeBarColor(for: index))
                                .frame(width: 7, height: 7)
                        }
                        // Right margin
                        Spacer()
                            .frame(width: 20)
                    }
                }
            }
            .frame(height: 60)
        }
        .frame(width: hudSize, height: hudSize)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .environment(\.colorScheme, .dark)
        )
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.2), value: isVisible)
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
        let threshold = Float(index) / 16.0
        if volume > threshold {
            return .white  // Active bars are white
        } else {
            return .white.opacity(0.2)  // Inactive bars are dim
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
