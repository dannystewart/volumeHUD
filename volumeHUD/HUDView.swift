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

fileprivate let shadowPadding: Double = 48

struct HUDView: View {
    // MARK: Properties

	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let hudType: HUDType
    let value: Float
    let isMuted: Bool
    let isVisible: Bool

	private let cornerRadius: Double = 18
    private let hudSize: Double = 200
	private let iconSize: Double = 80
	private let iconBoundsSize: Double = 112

	private let hudInsets = EdgeInsets(
		top: 31,
		leading: 0,
		bottom: 20,
		trailing: 0
	)

    // MARK: Computed Properties

	// SF Symbols has slight misalignment between speaker.slash.fill and speaker.fill
	private var speakerMutedIconOffset: Double {
		hudType == .volume && isMuted ? 3 : 0
	}

	private var iconStyle: some ShapeStyle {
		switch colorSchemeContrast {
			case .increased:
				HierarchicalShapeStyle.primary
			case _:
				colorScheme == .dark ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary
		}
	}

    // MARK: Content Properties

    var body: some View {
        VStack(spacing: 0) {
			// Icon
			Image(systemName: iconName, variableValue: Double(value))
				.font(.system(size: iconSize))
				.foregroundStyle(iconStyle)
				.offset(y: speakerMutedIconOffset)
				.frame(width: iconBoundsSize, height: iconBoundsSize)

			// Space divider
			Spacer()

			// The pip bar
			HUDProgressBar(value: Double(value))
				.disabled(isMuted)
        }
		.padding(hudInsets)
        .frame(width: hudSize, height: hudSize)
		.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
		.padding(shadowPadding) // allow some padding so the glass effect's subtle drop shadow isn't clipped
    }

    // MARK: Functions

    private var iconName: String {
        switch hudType {
			case .volume:
				if isMuted || value < 0.005 {
					"speaker.slash.fill"
				} else {
					"speaker.wave.3.fill"
				}

			case .brightness:
				"sun.max"
        }
    }
}

#Preview("Volume") {
	@Previewable @State var value: Float = 0.75

    ZStack {
        Color.gray

		VStack(spacing: 16) {
			HUDView(hudType: .volume, value: value, isMuted: false, isVisible: true)
				.padding(-shadowPadding) // counteract the shadow padding

			Slider(value: $value, in: 0...1, label: {
				Text("Volume")
			}, minimumValueLabel: {
				Text("")
			}, maximumValueLabel: {
				Text("\(String(format: "%.3f", value))")
					.monospacedDigit()
			})
			.frame(width: 280)

			VStack(spacing: 4) {
				let wholePips = floor(Double(value) * 16)
				let fractionPip = Double(value).truncatingRemainder(dividingBy: 1.0/16) * 16
				let quantizedPip = round(fractionPip * 4) / 4
				Text("Pips: \(String(format: "%02.2f", wholePips + quantizedPip))")
					.monospacedDigit()
			}
			.foregroundStyle(.secondary)
			.font(.subheadline)
		}
    }
	.frame(width: 320, height: 320)
}

#Preview("Mute") {
    ZStack {
        Color.gray

        HUDView(hudType: .volume, value: 0.0, isMuted: true, isVisible: true)
			.padding(-shadowPadding) // counteract the shadow padding
    }
	.frame(width: 320, height: 320)
}

#Preview("Brightness") {
	@Previewable @State var value: Float = 0.5

    ZStack {
        Color.gray

		VStack(spacing: 24) {
			HUDView(hudType: .brightness, value: value, isMuted: false, isVisible: true)
				.padding(-shadowPadding) // counteract the shadow padding

			Slider(value: $value, in: 0...1, label: {
				Text("Brightness")
			}, minimumValueLabel: {
				Text("")
			}, maximumValueLabel: {
				Text("\(String(format: "%.3f", value))")
					.monospacedDigit()
			})
			.frame(width: 280)

			VStack(spacing: 4) {
				let wholePips = floor(Double(value) * 16)
				let fractionPip = Double(value).truncatingRemainder(dividingBy: 1.0/16) * 16
				let quantizedPip = round(fractionPip * 4) / 4
				Text("Pips: \(String(format: "%02.2f", wholePips + quantizedPip))")
					.monospacedDigit()
			}
			.foregroundStyle(.secondary)
			.font(.subheadline)
		}
    }
	.frame(width: 320)
}
