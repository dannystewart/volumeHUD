//
//  SettingsView.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @State private var isUpdateAvailable = false
    @State private var isCheckingForUpdates = false
    @State private var isShowingUpdateResult = false
    @State private var updateMessage = ""

    @Environment(\.scenePhase) private var scenePhase

    let loginItemManager: LoginItemManager
    let onStyleChange: () -> Void
    let onBrightnessChange: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    SettingsRow(description: loginItemManager.lastError ?? "Start volumeHUD automatically when you log in") {
                        Toggle("Open at Login", isOn: Binding(
                            get: { loginItemManager.isEnabled },
                            set: { loginItemManager.setEnabled($0) },
                        ))
                    }
                    .onAppear { loginItemManager.updateStatus() }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { loginItemManager.updateStatus() }
                    }
                    #if !SANDBOX
                        BrightnessSetting(onChange: onBrightnessChange)
                    #endif
                }
                AppearanceSection(
                    onStyleChange: onStyleChange,
                )
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            SettingsFooter(
                isUpdateAvailable: isUpdateAvailable,
                isCheckingForUpdates: isCheckingForUpdates,
                onCheckForUpdates: { Task { await checkForUpdates() } },
                onQuit: onQuit,
            )
        }
        .frame(width: 480)
        #if !SANDBOX
            .task { await checkForUpdates(showResult: false) }
            .alert("Check for Updates", isPresented: $isShowingUpdateResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(updateMessage)
            }
        #endif // !SANDBOX
    }

    private func checkForUpdates(showResult: Bool = true) async {
        #if !SANDBOX
            guard !isCheckingForUpdates else { return }
            isCheckingForUpdates = true
            defer { isCheckingForUpdates = false }
            do {
                isUpdateAvailable = try await UpdateChecker.isUpdateAvailable()
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0"
                updateMessage = isUpdateAvailable ? "Update available!" : "volumeHUD \(version) is up to date."
            } catch {
                updateMessage = "Could not check for updates. \(error.localizedDescription)"
                Logger().error("Update check failed: \(error)")
            }
            // Available updates are shown inline; only explicit checks need other feedback.
            isShowingUpdateResult = showResult && !isUpdateAvailable
        #endif // !SANDBOX
    }
}

// MARK: - LoginItemSetting

private struct LoginItemSetting: View {
    @ObservedObject var loginItemManager: LoginItemManager

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SettingsRow(description: loginItemManager.lastError ?? "Start volumeHUD automatically when you log in") {
            Toggle("Open at Login", isOn: Binding(
                get: { loginItemManager.isEnabled },
                set: { loginItemManager.setEnabled($0) },
            ))
        }
        .onAppear { loginItemManager.updateStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loginItemManager.updateStatus() }
        }
    }
}

// MARK: - BrightnessSetting

#if !SANDBOX
    private struct BrightnessSetting: View {
        @AppStorage("brightnessEnabled") private var brightnessEnabled = false

        let onChange: () -> Void

        var body: some View {
            SettingsRow(description: "Show HUD for brightness changes (experimental; built-in display only)") {
                Toggle("Enable Brightness HUD", isOn: $brightnessEnabled)
                    .onChange(of: brightnessEnabled) { onChange() }
            }
        }
    }
#endif // !SANDBOX

// MARK: - AppearanceSection

private struct AppearanceSection: View {
    @AppStorage(HUDStyle.preferenceKey) private var hudStyle: HUDStyle = .classic
    @AppStorage("volumeHUDFollowsMouse") private var volumeHUDFollowsMouse = true
    @AppStorage("useRelativePositioning") private var useRelativePositioning = true

    let onStyleChange: () -> Void

    var body: some View {
        Section("Appearance") {
            SettingsRow(description: "Use the classic pre-Tahoe style or the modern glass appearance") {
                Picker("HUD Style", selection: $hudStyle) {
                    Text("Classic Mac").tag(HUDStyle.classic)
                    Text("Modern Glass").tag(HUDStyle.modern)
                }
                .onChange(of: hudStyle) { onStyleChange() }
            }

            SettingsRow(description: "Show the HUD on the primary display or the display with the mouse cursor") {
                Picker("HUD Display", selection: $volumeHUDFollowsMouse) {
                    Text("Always Use Primary Display").tag(false)
                    Text("Follow Mouse Cursor").tag(true)
                }
            }

            SettingsRow(description: "How to position the HUD relative to the bottom of the screen") {
                Picker("Position From Bottom", selection: $useRelativePositioning) {
                    Text("Absolute Distance").tag(false)
                    Text("Relative Percentage").tag(true)
                }
            }
        }
    }
}

// MARK: - SettingsFooter

private struct SettingsFooter: View {
    @Environment(\.openURL) private var openURL

    let isUpdateAvailable: Bool
    let isCheckingForUpdates: Bool
    let onCheckForUpdates: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                #if !SANDBOX
                    if isUpdateAvailable {
                        Button("Update Available") {
                            openURL(URL(string: "https://github.com/dannystewart/volumeHUD/releases/latest")!)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else {
                        Button("Check for Updates", action: onCheckForUpdates)
                            .disabled(isCheckingForUpdates)
                    }
                #endif // !SANDBOX
                Spacer()
                Button(action: onQuit) {
                    Text("Quit volumeHUD")
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
        }
    }
}

// MARK: - SettingsRow

/// A native form control with an optional secondary caption.
struct SettingsRow<Content: View>: View {
    private let description: String?
    private let content: Content

    init(description: String? = nil, @ViewBuilder content: () -> Content) {
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    SettingsView(
        loginItemManager: LoginItemManager(),
        onStyleChange: {},
        onBrightnessChange: {},
        onQuit: {},
    )
}
