//
//  LoginHelper.swift
//  by Danny Stewart (2025)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import AppKit

// MARK: - LoginHelperDelegate

/// Simple helper app delegate that launches the main volumeHUD app and then quits
@MainActor
class LoginHelperDelegate: NSObject, NSApplicationDelegate {
    /// Shared UserDefaults key for login helper launch marker
    private let launchMarkerKey = "loginHelperLaunchTimestamp"

    func applicationDidFinishLaunching(_: Notification) {
        // Get the main app bundle URL (helper is at .../volumeHUD.app/Contents/Library/LoginItems/LoginHelper.app)
        let helperURL = Bundle.main.bundleURL
        let loginItemsURL = helperURL.deletingLastPathComponent()
        let libraryURL = loginItemsURL.deletingLastPathComponent()
        let contentsURL = libraryURL.deletingLastPathComponent()
        let mainAppURL = contentsURL.deletingLastPathComponent()

        // Write a timestamp marker to UserDefaults BEFORE launching the main app
        // This is more reliable than command line arguments which may not be passed through
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: launchMarkerKey)
        UserDefaults.standard.synchronize()

        // Launch the main app
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false // Don't activate the main app (it's a background utility)

        NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration) { _, error in
            if let error {
                NSLog("LoginHelper: Failed to launch volumeHUD: \(error)")
            }
            // Exit the helper regardless of success/failure
            NSApp.terminate(nil)
        }
    }
}

/// Entry point
func main() {
    let app = NSApplication.shared
    let delegate = LoginHelperDelegate()
    app.delegate = delegate
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}

main()
