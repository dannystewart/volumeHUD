import SwiftUI

struct HUDProgressBar: View {
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.colorSchemeContrast) private var colorSchemeContrast
	@Environment(\.isEnabled) private var isEnabled

	var value: Double
	var pips: UInt = 16
	var pipParts: UInt = 4

	private let pipWidth: Double = 9
	private let pipHeight: Double = 6
	
	private var barWidth: Double { Double(pips) * pipWidth + Double(pips+1) }
	private var barHeight: Double { pipHeight + 2 }

	/// The number of pips that should be shown for the current input value.
	private var shownPipsNum: Int {
		Int(floor(value * Double(pips)))
	}

	private var pipOpacity: Double {
		let enabledMult = isEnabled ? 1.0 : 0.35
		if colorSchemeContrast == .increased {
			return isEnabled ? 1.0 : 0.5
		}

		return (colorScheme == .dark ? 0.6 : 0.9) * enabledMult
	}

	private var pip: some View {
		Rectangle()
			.fill(.white.opacity(pipOpacity))
			.frame(height: pipHeight)
	}

	/// The width of the last fractional pip that might be shown *in addition* to the `shownPipsNum` pips that are already visible.
	/// Contained to the range `0...1`, in increments of `0.25`.
	private var fractionalPipWidth: Double {
		let parts = Double(max(1, pipParts))
		let onePip = 1 / Double(max(1, pips))
		let fractionPipWidth = value.truncatingRemainder(dividingBy: onePip) * Double(pips)
		let quantizedPipWidth = round(fractionPipWidth * parts) / parts
		return quantizedPipWidth
	}

    var body: some View {
		ZStack(alignment: .leading) {
			// The pip bar's background
			Rectangle()
				.fill(.secondary)
				.environment(\.colorScheme, .light) // ensures the background always uses a dark color

			HStack(spacing: 1) {
				// Show "whole" pips first
				ForEach(0 ..< shownPipsNum, id: \.self) { index in
					pip.frame(width: pipWidth)
				}

				// Show a fractional pip, if applicable
				if fractionalPipWidth > 0 {
					pip.frame(width: pipWidth * fractionalPipWidth)
				}
			}
			.padding(1)
		}
		.frame(width: barWidth, height: barHeight)
    }
}

#Preview ("HUDProgressBar"){
	@Previewable @State var value: Double = 0.5

	ZStack {
		Color.gray

		VStack(spacing: 24) {
			HUDProgressBar(value: value)

			Slider(value: $value, in: 0...1, label: {
				Text("Value")
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
				Text("Pips: \(String(format: "%.2f", wholePips + quantizedPip))")
					.monospacedDigit()
			}
			.foregroundStyle(.secondary)
			.font(.subheadline)
		}
	}
	.frame(width: 320, height: 140)
}
