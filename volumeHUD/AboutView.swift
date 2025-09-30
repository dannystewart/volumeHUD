import SwiftUI

struct AboutView: View {
    let onQuit: () -> Void

    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "2.0.0"
    }

    var body: some View {
        VStack(spacing: 20) {
            // App icon
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
            }

            // App name and version
            VStack(spacing: 4) {
                Text("volumeHUD")
                    .font(.system(size: 24, weight: .medium))

                Text("by Danny Stewart")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text("Version \(appVersion)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Description
            Text("Bringing the classic volume HUD back to your Mac")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 160)

            Spacer()
                .frame(height: 8)

            // Quit button
            Button(action: onQuit) {
                Text("Quit volumeHUD")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(30)
        .frame(width: 270, height: 400)
    }
}
