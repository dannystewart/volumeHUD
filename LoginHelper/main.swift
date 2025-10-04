import AppKit

// MARK: - LoginHelperDelegate

// Simple helper app delegate that launches the main volumeHUD app and then quits
@MainActor
class LoginHelperDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // Get the main app bundle URL (helper is at .../volumeHUD.app/Contents/Library/LoginItems/LoginHelper.app)
        let helperURL = Bundle.main.bundleURL
        let loginItemsURL = helperURL.deletingLastPathComponent()
        let libraryURL = loginItemsURL.deletingLastPathComponent()
        let contentsURL = libraryURL.deletingLastPathComponent()
        let mainAppURL = contentsURL.deletingLastPathComponent()

        // Launch the main app with a marker argument to indicate it was launched by login item
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false // Don't activate the main app (it's a background utility)
        configuration.arguments = ["--launchedByLoginItem"]

        NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration) { _, error in
            if let error {
                NSLog("LoginHelper: Failed to launch volumeHUD: \(error)")
            }
            // Exit the helper regardless of success/failure
            NSApp.terminate(nil)
        }
    }
}

// Entry point
func main() {
    let app = NSApplication.shared
    let delegate = LoginHelperDelegate()
    app.delegate = delegate
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}

main()
