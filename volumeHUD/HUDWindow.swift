import AppKit

class HUDWindow: NSWindow {
	convenience init() {
		self.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
		self.windowSetup()
	}

	override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
		super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
		self.windowSetup()
	}

	private func windowSetup() {
		self.collectionBehavior = [.canJoinAllApplications, .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
		self.level = .statusBar + 1
		self.isOpaque = false
		self.hasShadow = false
		self.backgroundColor = .clear
		self.ignoresMouseEvents = true
		self.isMovable = false
		self.canHide = false
	}

	// needed so glass and blur effects look good
	override func _hasActiveAppearance() -> Bool { true }
}
