import AppKit

class HUDWindow: NSWindow {
	// taken from macOS Tahoe's arm64 slice of /System/Library/CoreServices/OSDUIHelper.app/Contents/MacOS/OSDUIHelper
	private let hudWindowLevel = NSWindow.Level(0x7d5)

	convenience init() {
		let size = CGSize(
			width: HUDView.hudSize + HUDView.shadowPadding * 2,
			height: HUDView.hudSize + HUDView.shadowPadding * 2,
		)
		self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
		self.windowSetup()
	}

	private func windowSetup() {
		self.collectionBehavior = [.canJoinAllApplications, .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
		self.level = hudWindowLevel

		self.isOpaque = false
		self.hasShadow = false
		self.backgroundColor = .clear
		self.ignoresMouseEvents = true
		self.isMovable = false
		self.canHide = false
	}

	// needed so glass and blur effects never revert to their inactive style
	override func _hasActiveAppearance() -> Bool { true }
}
