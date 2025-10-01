import Polykit
import SwiftUI

struct AboutView: View {
    let onQuit: () -> Void
    let logger = PolyLog()

    // State to track if an update is available
    @State private var isUpdateAvailable: Bool = false

    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "1.3.0" // The update check was introduced in 1.3.0
    }

    // GitHub repository info
    private let githubOwner = "dannystewart"
    private let githubRepo = "volumeHUD"

    private func checkForUpdates() {
        Task {
            do {
                let latestRelease = try await fetchLatestRelease()

                // Compare versions
                if isNewerVersion(latestRelease, than: appVersion) {
                    await MainActor.run {
                        isUpdateAvailable = true
                    }
                }
            } catch { // Silently fail if the update check fails
                logger.error("Update check failed: \(error)")
            }
        }
    }

    private func fetchLatestRelease() async throws -> String {
        let urlString = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }

        // Parse JSON response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String
        else {
            throw URLError(.cannotParseResponse)
        }

        // Remove 'v' prefix
        return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    private func isNewerVersion(_ latest: String, than current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        // Compare version components (major.minor.patch)
        for i in 0 ..< max(latestComponents.count, currentComponents.count) {
            let latestPart = i < latestComponents.count ? latestComponents[i] : 0
            let currentPart = i < currentComponents.count ? currentComponents[i] : 0

            if latestPart > currentPart {
                return true
            } else if latestPart < currentPart {
                return false
            }
        }

        return false // Versions are equal
    }

    private func openReleasesPage() {
        let urlString = "https://github.com/\(githubOwner)/\(githubRepo)/releases/latest"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
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

                // Update check
                Button(action: openReleasesPage) {
                    Text("Update available!")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(!isUpdateAvailable)
                .opacity(isUpdateAvailable ? 1.0 : 0.0)
            }

            // Description
            Text("Bringing the classic volume and brightness HUD back to your Mac")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 180)

            Spacer()
                .frame(height: 20)

            // Quit button
            Button(action: onQuit) {
                Text("Quit volumeHUD")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(width: 270, height: 380)
        .onAppear {
            checkForUpdates()
        }
    }
}

#Preview {
    AboutView(onQuit: {
        print("Quit button pressed")
    })
}
