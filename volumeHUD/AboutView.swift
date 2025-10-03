import Polykit
import SwiftUI

struct AboutView: View {
    let onQuit: () -> Void
    weak var appDelegate: AppDelegate?

    let logger = PolyLog()

    // Settings for app preferences
    @AppStorage("brightnessEnabled") private var brightnessEnabled: Bool = false
    @AppStorage("shareLogsEnabled") private var shareLogsEnabled: Bool = false

    // State to track if an update is available
    @State private var isUpdateAvailable: Bool = false

    // GitHub repository info
    private let githubOwner = "dannystewart"
    private let githubRepo = "volumeHUD"

    // Get the app version
    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "2.0.0"
    }

    // MARK: - About View

    var body: some View {
        VStack(spacing: 8) {
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
                    .foregroundStyle(.secondary)

                Text("Version \(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                // Update check
                Button(action: openReleasesPage) {
                    Text("Update available!")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                        .underline()
                        .frame(minHeight: 20)
                }
                .buttonStyle(.plain)
                .disabled(!isUpdateAvailable)
                .opacity(isUpdateAvailable ? 1.0 : 0.0)
            }

            // Description
            Text("Bringing the classic HUD back to your Mac")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 140, minHeight: 40, alignment: .init(horizontal: .center, vertical: .center))

            // Settings section
            VStack(spacing: 8) {
                Spacer()
                    .frame(height: 10)

                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 14))

                        Text("Brightness HUD")
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        Toggle("", isOn: $brightnessEnabled)
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                            .scaleEffect(0.8)
                            .onChange(of: brightnessEnabled) { oldValue, newValue in
                                logger.debug("Brightness setting changed from \(oldValue) to \(newValue).")
                                appDelegate?.startBrightnessMonitoringIfEnabled()
                            }
                    }
                    .padding(.horizontal, 20)

                    Text("Experimental, built-in display only")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .opacity(0.8)
                        .frame(height: 16, alignment: .init(horizontal: .center, vertical: .top))
                }

                Spacer().frame(height: 2)

                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))

                        Text("Share Logs")
                            .font(.system(size: 12, weight: .medium))

                        Spacer()

                        Toggle("", isOn: $shareLogsEnabled)
                            .toggleStyle(SwitchToggleStyle())
                            .scaleEffect(0.8)
                            .onChange(of: shareLogsEnabled) { oldValue, newValue in
                                logger.debug("Share Logs setting changed from \(oldValue) to \(newValue).")
                            }
                    }
                    .padding(.horizontal, 20)

                    Text("100% anonymous, helps me improve")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .frame(height: 16, alignment: .init(horizontal: .center, vertical: .top))
                        .opacity(0.8)
                }
            }

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
        .frame(width: 300, height: 490)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                checkForUpdates()
            }
        }
    }

    // MARK: - Check for Updates

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

    // MARK: - Fetch Latest Release

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
}

#Preview {
    AboutView(
        onQuit: { print("Quit button pressed") },
        appDelegate: nil,
    )
}
