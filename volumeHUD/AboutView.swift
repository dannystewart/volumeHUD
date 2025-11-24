//
//  AboutView.swift
//  by Danny Stewart (2025)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import PolyKit
import SwiftUI

// MARK: - AboutView

struct AboutView: View {
    let onQuit: () -> Void
    weak var appDelegate: AppDelegate?

    let logger: PolyLog = .init()

    /// Settings for app preferences
    @AppStorage("brightnessEnabled") private var brightnessEnabled: Bool = false
    @AppStorage("volumeHUDFollowsMouse") private var volumeHUDFollowsMouse: Bool = false
    @AppStorage("useRelativePositioning") private var useRelativePositioning: Bool = true
    @AppStorage("hideSystemVolumeHUD") private var hideSystemVolumeHUD: Bool = false

    /// State to track if an update is available
    @State private var isUpdateAvailable: Bool = false

    /// Login item manager
    @ObservedObject var loginItemManager: LoginItemManager

    // GitHub repository info
    private let githubOwner = "dannystewart"
    private let githubRepo = "volumeHUD"

    // Visual alignment
    private let iconColumnWidth: CGFloat = 20
    private let minSettingColumnWidth: CGFloat = 140
    private let settingPadding: CGFloat = 24 // Higher for less padding
    private let spaceBeforeSubtitle: CGFloat = -3

    /// Get the app version
    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "2.0.0"
    }

    // MARK: - About View

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // MARK: - Left Column (App Info and Quit Button)

            VStack(spacing: 8) {
                if let appIcon = NSImage(named: "volumeHUD") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 80, height: 80)
                }
                Text("volumeHUD")
                    .font(.system(size: 24, weight: .medium))
                Text("by Danny Stewart")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("Version \(appVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button(action: openReleasesPage) {
                    Text("Update available!")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                        .underline()
                }
                .buttonStyle(.plain)
                .disabled(!isUpdateAvailable)
                .opacity(isUpdateAvailable ? 1.0 : 0.0)
                .padding(.bottom, 16)

                Spacer(minLength: 0)

                Button(action: onQuit) {
                    Text("Quit volumeHUD")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .frame(width: 160, alignment: .top)
            .padding(.leading, 16)

            // MARK: - Right Column (Settings)

            VStack(alignment: .leading, spacing: 15) {
                // MARK: - Open at Login Setting

                VStack(alignment: .leading, spacing: spaceBeforeSubtitle) {
                    HStack(alignment: .center, spacing: iconColumnWidth) {
                        Image(systemName: "power.circle.fill")
                            .foregroundStyle(loginItemManager.isEnabled ? .green : .gray)
                            .font(.system(size: 14))
                            .frame(width: 14, alignment: .leading)
                            .animation(.easeInOut(duration: 0.3), value: loginItemManager.isEnabled)

                        Text("Open at Login")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: minSettingColumnWidth, alignment: .leading)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { loginItemManager.isEnabled },
                            set: { loginItemManager.setEnabled($0) },
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .scaleEffect(0.8)
                    }
                }
                .padding(.leading, settingPadding)

                // MARK: - Hide System Volume HUD Toggle

                VStack(alignment: .leading, spacing: spaceBeforeSubtitle) {
                    HStack(alignment: .center, spacing: iconColumnWidth) {
                        Image(systemName: "speaker.slash.fill")
                            .foregroundStyle(hideSystemVolumeHUD ? .purple : .gray)
                            .font(.system(size: 14))
                            .frame(width: 14, alignment: .leading)
                            .animation(.easeInOut(duration: 0.3), value: hideSystemVolumeHUD)

                        Text("Hide System HUD")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: minSettingColumnWidth, alignment: .leading)

                        Spacer()

                        Toggle("", isOn: $hideSystemVolumeHUD)
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                            .scaleEffect(0.8)
                            .onChange(of: hideSystemVolumeHUD) { oldValue, newValue in
                                logger.debug("Hide system HUD setting changed from \(oldValue) to \(newValue).")
                                appDelegate?.updateMediaKeyInterceptor()
                            }
                    }

                    HStack(spacing: iconColumnWidth) {
                        Spacer()
                            .frame(width: 14)

                        Text(hideSystemVolumeHUD ? "Intercept keys to hide macOS HUD" : "Show both volumeHUD and macOS HUD")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .opacity(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, settingPadding)
                .animation(.easeInOut(duration: 0.3), value: hideSystemVolumeHUD)

                // MARK: - Brightness HUD Toggle

                VStack(alignment: .leading, spacing: spaceBeforeSubtitle) {
                    HStack(alignment: .center, spacing: iconColumnWidth) {
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(brightnessEnabled ? .orange : .gray)
                            .font(.system(size: 14))
                            .frame(width: 14, alignment: .leading)
                            .animation(.easeInOut(duration: 0.3), value: brightnessEnabled)

                        Text("Brightness HUD")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: minSettingColumnWidth, alignment: .leading)

                        Spacer()

                        Toggle("", isOn: $brightnessEnabled)
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                            .scaleEffect(0.8)
                            .onChange(of: brightnessEnabled) { oldValue, newValue in
                                logger.debug("Brightness setting changed from \(oldValue) to \(newValue).")
                                appDelegate?.startBrightnessMonitoringIfEnabled()
                            }
                    }

                    HStack(spacing: iconColumnWidth) {
                        Spacer()
                            .frame(width: 14)

                        Text("Experimental, built-in display only")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .opacity(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, settingPadding)
                .animation(.easeInOut(duration: 0.3), value: brightnessEnabled)

                // MARK: - Display Toggle for HUD Placement

                VStack(alignment: .leading, spacing: spaceBeforeSubtitle) {
                    HStack(alignment: .center, spacing: iconColumnWidth) {
                        Image(systemName: volumeHUDFollowsMouse ? "cursorarrow.click.2" : "laptopcomputer")
                            .foregroundStyle(volumeHUDFollowsMouse ? .blue : .gray)
                            .font(.system(size: 14))
                            .frame(width: 14, alignment: .leading)
                            .animation(.easeInOut(duration: 0.3), value: volumeHUDFollowsMouse)

                        Text("HUD Follows Mouse")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: minSettingColumnWidth, alignment: .leading)

                        Spacer()

                        Toggle("", isOn: $volumeHUDFollowsMouse)
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                            .scaleEffect(0.8)
                            .onChange(of: volumeHUDFollowsMouse) { oldValue, newValue in
                                logger.debug("Volume HUD display setting changed from \(oldValue) to \(newValue).")
                            }
                    }

                    HStack(spacing: iconColumnWidth) {
                        Spacer()
                            .frame(width: 14)

                        Text(volumeHUDFollowsMouse ? "Show on screen with mouse cursor" : "Always show on the primary display")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .opacity(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, settingPadding)
                .animation(.easeInOut(duration: 0.3), value: volumeHUDFollowsMouse)

                // MARK: - Relative Positioning Toggle

                VStack(alignment: .leading, spacing: spaceBeforeSubtitle) {
                    HStack(alignment: .center, spacing: iconColumnWidth) {
                        Image(systemName: useRelativePositioning ? "arrow.up.and.down.text.horizontal" : "arrow.down.to.line")
                            .foregroundStyle(useRelativePositioning ? .cyan : .gray)
                            .font(.system(size: 14))
                            .frame(width: 14, alignment: .leading)
                            .animation(.easeInOut(duration: 0.3), value: useRelativePositioning)

                        Text("Relative HUD Position")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: minSettingColumnWidth, alignment: .leading)

                        Spacer()

                        Toggle("", isOn: $useRelativePositioning)
                            .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                            .scaleEffect(0.8)
                            .onChange(of: useRelativePositioning) { oldValue, newValue in
                                logger.debug("Relative positioning setting changed from \(oldValue) to \(newValue).")
                            }
                    }

                    HStack(spacing: iconColumnWidth) {
                        Spacer()
                            .frame(width: 14)

                        Text(useRelativePositioning ? "Relative percentage from bottom" : "Absolute from bottom (Apple default)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .opacity(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, settingPadding)
                .animation(.easeInOut(duration: 0.3), value: useRelativePositioning)

                Spacer(minLength: 0)
            }
            .padding(.trailing, 6) // Right side window padding
        }
        .padding(32) // Overall frame padding
        .frame(width: 540, height: 300)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 200000000) // 0.2 second delay
                checkForUpdates()
            }
        }
    }

    // MARK: - Update Check

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

        guard
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200 else
        {
            throw URLError(.badServerResponse)
        }

        // Parse JSON response
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tagName = json["tag_name"] as? String else
        {
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
    class MockLoginItemManager: LoginItemManager {
        override init() {
            super.init()
            isEnabled = true
        }

        override func setEnabled(_ enabled: Bool) { isEnabled = enabled }
        override func updateStatus() {}
    }

    return AboutView(
        onQuit: {},
        appDelegate: nil,
        loginItemManager: MockLoginItemManager(),
    )
}
