import Polykit
import SwiftUI

struct AboutView: View {
    let onQuit: () -> Void
    weak var appDelegate: AppDelegate?

    let logger = PolyLog()

    // Settings for app preferences
    @AppStorage("brightnessEnabled") private var brightnessEnabled: Bool = false
    @AppStorage("brightnessDetectionMode") private var brightnessDetectionMode: String = "heuristic"

    // State to track if an update is available
    @State private var isUpdateAvailable: Bool = false

    // Login item manager
    @StateObject private var loginItemManager = LoginItemManager()

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

    // Check if we're using Heuristics mode but don't have Accessibility permissions
    private var usingHeuristicsWithoutAccessibility: Bool {
        brightnessEnabled && brightnessDetectionMode == "heuristic" && !AXIsProcessTrusted()
    }

    // MARK: - About View

    var body: some View {
        VStack(spacing: 8) {
            // App name and version
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .offset(y: -20)
            }

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

                // Description
                Text("Bringing the classic HUD back to your Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 230, height: 10)
                    .offset(y: -8)

            }.offset(y: -20)

            // Settings section
            VStack(spacing: 6) {
                // Login item setting
                HStack {
                    Image(systemName: "power.circle.fill")
                        .foregroundStyle(loginItemManager.isEnabled ? .green : .gray)
                        .font(.system(size: 14))
                        .animation(.easeInOut(duration: 0.3), value: loginItemManager.isEnabled)

                    Text("Open at Login")
                        .font(.system(size: 12, weight: .medium))

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { loginItemManager.isEnabled },
                        set: { loginItemManager.setEnabled($0) },
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .scaleEffect(0.8)
                }
                .padding(.horizontal, 14)

                VStack(spacing: 6) {
                    // Brightness HUD setting
                    HStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(brightnessEnabled ? .orange : .gray)
                            .font(.system(size: 14))
                            .animation(.easeInOut(duration: 0.3), value: brightnessEnabled)

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
                    .padding(.horizontal, 14)

                    Text("Experimental, built-in display only")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .opacity(0.8)
                        .frame(height: 16, alignment: .init(horizontal: .center, vertical: .top))
                        .offset(y: -2)

                    // Detection mode picker (only shown when brightness is enabled)
                    HStack {
                        Text("Mode")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 34)
                            .offset(x: 11, y: 0)
                        Spacer()
                        Picker("", selection: $brightnessDetectionMode) {
                            Text(" Step-based ").tag("stepBased")
                            Text("Heuristic").tag("heuristic")
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .scaleEffect(0.9)
                        .onChange(of: brightnessDetectionMode) { oldValue, newValue in
                            logger.debug("Brightness detection mode changed from \(oldValue) to \(newValue).")
                            updateBrightnessDetectionMode()
                        }
                        .allowsHitTesting(brightnessEnabled)
                    }
                    .padding(.horizontal, 14)
                    .opacity(brightnessEnabled ? 1.0 : 0.0)
                    .offset(y: brightnessEnabled ? 0 : -8)
                }
                .animation(.easeInOut(duration: 0.3), value: brightnessEnabled)

                Text("⚠️  Accessibility permissions needed")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .opacity(0.8)
                    .frame(width: 250, height: 16, alignment: .init(horizontal: .center, vertical: .top))
                    .offset(y: usingHeuristicsWithoutAccessibility ? 0 : -3)
                    .opacity(usingHeuristicsWithoutAccessibility ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.1), value: usingHeuristicsWithoutAccessibility)

                Spacer().frame(height: 2)
            }.offset(y: -4)

            // Quit button
            Button(action: onQuit) {
                Text("Quit volumeHUD")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .offset(y: 12)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 300, height: 450)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second delay
                checkForUpdates()
            }
            // Update the brightness detection mode when the view appears
            updateBrightnessDetectionMode()
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

    private func updateBrightnessDetectionMode() {
        guard let brightnessMonitor = appDelegate?.brightnessMonitor else { return }

        switch brightnessDetectionMode {
        case "stepBased":
            brightnessMonitor.detectionMode = .stepBased
        case "heuristic":
            brightnessMonitor.detectionMode = .heuristic
        default:
            brightnessMonitor.detectionMode = .stepBased
        }

        logger.debug("Updated brightness detection mode to: \(brightnessDetectionMode)")
    }
}

#Preview {
    AboutView(
        onQuit: { print("Quit button pressed") },
        appDelegate: nil,
    )
}
