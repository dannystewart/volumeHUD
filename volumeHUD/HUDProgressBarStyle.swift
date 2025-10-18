import SwiftUI

struct HUDProgressBarStyle: ProgressViewStyle {
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.colorSchemeContrast) private var colorSchemeContrast
	@Environment(\.isEnabled) private var isEnabled

	var pips: UInt = 16
	var pipParts: UInt = 4

	private let pipWidth: Double = 9
	private let pipHeight: Double = 6
	private var barWidth: Double { Double(pips) * pipWidth + Double(pips+1) } // 161
	private var barHeight: Double { pipHeight + 2 } // 8

	private let padding: Double = 1

	private var pipOpacity: Double {
		if colorSchemeContrast == .standard {
			isEnabled ? 1.0 : 0.5
		} else {
			isEnabled ? 1.0 : 0.65
		}
	}

	private var pip: some View {
		Rectangle()
			.fill(.pipsFill)
			.opacity(pipOpacity)
	}

	/// The number of pips that should be shown for the current input value.
	private func shownPipsNum(value: Double) -> Int {
		Int(floor(value * Double(pips)))
	}

	/// The width of the last fractional pip that might be shown *in addition* to the `shownPipsNum` pips that are already visible.
	/// Contained to the range `0...1`, in increments of `0.25`.
	private func fractionalPipWidth(value: Double) -> Double {
		let parts = Double(max(1, pipParts))
		let onePip = 1 / Double(max(1, pips))
		let fractionPipWidth = value.truncatingRemainder(dividingBy: onePip) * Double(pips)
		let quantizedPipWidth = round(fractionPipWidth * parts) / parts
		return quantizedPipWidth
	}

	func makeBody(configuration: Configuration) -> some View {
		ZStack(alignment: .leading) {
			// The pip bar's background
			Rectangle()
				.fill(.pipsBackground)

			let value = configuration.fractionCompleted ?? 0
			let shownPips = shownPipsNum(value: value)
			let fractionalPipWidth = fractionalPipWidth(value: value)

			HStack(spacing: padding) {
				// Show "whole" pips first
				ForEach(0 ..< shownPips, id: \.self) { index in
					pip.frame(width: pipWidth)
				}

				// Show a fractional pip, if applicable
				if fractionalPipWidth > 0 {
					pip.frame(width: pipWidth * fractionalPipWidth)
				}
			}
			.padding(padding)
		}
		.frame(width: barWidth, height: barHeight)
	}
}

extension ProgressViewStyle where Self == HUDProgressBarStyle {
	static var hud: HUDProgressBarStyle {
		HUDProgressBarStyle()
	}
}


#Preview ("HUDProgressBarStyle"){
	@Previewable @State var value: Double = 0.5
	@Previewable @State var disabled: Bool = false

	ZStack {
		Color.gray

		VStack(spacing: 12) {
			ProgressView(value: value)
				.progressViewStyle(.hud)
				.disabled(disabled)

			let wholePips = floor(Double(value) * 16)
			let fractionPip = Double(value).truncatingRemainder(dividingBy: 1.0/16) * 16
			let quantizedPip = round(fractionPip * 4) / 4
			Text("Pips: \(String(format: "%.2f", wholePips + quantizedPip))")
				.monospacedDigit()
				.foregroundStyle(.secondary)
				.font(.subheadline)

			Slider(value: $value, in: 0...1, label: {
				Text("Value")
			}, minimumValueLabel: {
				Text("")
			}, maximumValueLabel: {
				Text("\(String(format: "%.3f", value))")
					.monospacedDigit()
			})
			.frame(width: 280)

			Toggle("Disabled", isOn: $disabled)
		}
	}
	.frame(width: 320, height: 140)
}
