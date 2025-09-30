import SwiftUI

enum HUDType {
    case volume
    case brightness
}

struct UnifiedHUDView: View {
    let hudType: HUDType
    let value: Float
    let isMuted: Bool
    let isVisible: Bool

    private let hudSize: CGFloat = 200
    private let iconSize: CGFloat = 80

    var body: some View {
        VStack(spacing: 0) {
            VStack { // Icon section
                Spacer()
                    .frame(height: 56)
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
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
                .environment(\.colorScheme, .dark)
        )
        .opacity(isVisible ? 1.0 : 0.0)
    }

    private var iconName: String {
        switch hudType {
        case .volume:
            if isMuted {
                return "speaker.slash.fill"
            } else if value < 0.08 {
                return "speaker.fill"
            } else if value < 0.33 {
                return "speaker.wave.1.fill"
            } else if value < 0.66 {
                return "speaker.wave.2.fill"
            } else {
                return "speaker.wave.3.fill"
            }
        case .brightness:
            return "sun.max.fill"
        }
    }

    private func barColor(for index: Int) -> Color {
        if hudType == .volume && isMuted {
            return .white.opacity(0.2)
        }

        let threshold = Float(index) / 16.0
        if value > threshold {
            return .white.opacity(0.8)
        } else {
            return .white.opacity(0.2)
        }
    }
}

#Preview("Volume") {
    ZStack {
        Color.black.ignoresSafeArea()
        UnifiedHUDView(hudType: .volume, value: 0.7, isMuted: false, isVisible: true)
    }
}

#Preview("Brightness") {
    ZStack {
        Color.black.ignoresSafeArea()
        UnifiedHUDView(hudType: .brightness, value: 0.5, isMuted: false, isVisible: true)
    }
}
