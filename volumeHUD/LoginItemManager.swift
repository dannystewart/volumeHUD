import Combine
import Foundation
import Polykit
import ServiceManagement

/// Manages login item functionality using the modern SMAppService API
@MainActor
class LoginItemManager: ObservableObject {
    private let logger = PolyLog()
    private let helperBundleIdentifier = "com.dannystewart.volumehud.loginhelper"

    @Published var isEnabled: Bool = false
    @Published private(set) var lastError: String?

    private var isUpdatingFromSystem = false

    private var service: SMAppService {
        SMAppService.loginItem(identifier: helperBundleIdentifier)
    }

    init() {
        updateStatus()
    }

    /// Updates the current login item status from the system
    func updateStatus() {
        isUpdatingFromSystem = true
        isEnabled = service.status == .enabled
        isUpdatingFromSystem = false
        logger.debug("Login item status: \(service.status)")
    }

    /// Sets the login item state
    func setEnabled(_ enabled: Bool) {
        guard !isUpdatingFromSystem else { return }
        guard enabled != isEnabled else { return }

        do {
            if enabled {
                try service.register()
                logger.info("Login item enabled.")
            } else {
                try service.unregister()
                logger.info("Login item disabled.")
            }
            lastError = nil
            updateStatus()
        } catch {
            logger.error("Failed to set login item: \(error)")
            lastError = error.localizedDescription
        }
    }

    /// Toggles the login item on or off
    func toggle() {
        setEnabled(!isEnabled)
    }
}
