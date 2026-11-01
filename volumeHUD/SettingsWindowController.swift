//
//  SettingsWindowController.swift
//  by Danny Stewart (2026)
//  MIT License
//  https://github.com/dannystewart/volumeHUD
//

import AppKit
import SwiftUI

// MARK: - SettingsWindowController

/// Owns the native Settings scene and the temporary foreground presentation of this headless app.
@MainActor
final class SettingsWindowController: NSObject {
    private var openSettings: (() -> Void)?
    private weak var window: NSWindow?
    private weak var aboutWindow: NSWindow?
    private var isSettingsOpen = false
    private var previousMenu: NSMenu?
    private var previousActivationPolicy: NSApplication.ActivationPolicy?
    private var isActivationHandoffPending = false
    private var activationHandoffPID: pid_t?
    private lazy var settingsMenu = makeMenu()
    #if !SANDBOX
        private var updateItem: NSMenuItem?
        private var updateCheck: Task<Void, Never>?
    #endif
    private let onQuit: () -> Void

    init(onQuit: @escaping () -> Void) {
        self.onQuit = onQuit
    }

    /// Scene representations must be registered during applicationWillFinishLaunching.
    func install(@ViewBuilder content: () -> some View) {
        let content = content()
        let scene = NSHostingSceneRepresentation {
            Settings {
                content.background(SettingsWindowConnection(controller: self))
            }
            .windowResizability(.contentSize)
        }
        NSApp.addSceneRepresentation(scene)
        openSettings = { scene.environment.openSettings() }
    }

    @objc func open() {
        beginPresentation()
        isSettingsOpen = true
        openSettings?()
        window?.makeKeyAndOrderFront(nil)
        #if !SANDBOX
            if updateCheck == nil {
                updateCheck = Task { [weak self] in
                    do {
                        let available = try await UpdateChecker.isUpdateAvailable()
                        self?.updateItem?.isHidden = !available
                    } catch {
                        Logger().error("Update check failed: \(error)")
                    }
                    self?.updateCheck = nil
                }
            }
        #endif // !SANDBOX
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        if let previousWindow = self.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: previousWindow)
        }
        self.window = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window,
        )
    }

    private func beginPresentation() {
        if previousActivationPolicy == nil {
            previousActivationPolicy = NSApp.activationPolicy()
            previousMenu = NSApp.mainMenu
        }
        let isChangingPolicy = NSApp.activationPolicy() != .regular
        if isChangingPolicy {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.mainMenu = settingsMenu
        if isChangingPolicy {
            isActivationHandoffPending = true
            // Run after the Settings scene has ordered its window. A real application switch
            // is needed here: deactivate() alone leaves first-open menu tracking unresponsive.
            DispatchQueue.main.async { [weak self] in
                guard let self, isActivationHandoffPending else { return }
                beginActivationHandoff()
            }
        } else if !isActivationHandoffPending {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func beginActivationHandoff() {
        // The Dock provides a stable activation target without raising another app's windows.
        guard
            let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
            !dock.isActive else
        {
            completeActivationHandoff()
            return
        }
        activationHandoffPID = dock.processIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activationHandoffDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
        )
        if !dock.activate(options: []) {
            completeActivationHandoff()
        }
    }

    @objc private func activationHandoffDidActivate(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            application.processIdentifier == activationHandoffPID else { return }
        // Finish processing the Dock's activation before asking to activate volumeHUD.
        DispatchQueue.main.async { [weak self] in
            guard let self, isActivationHandoffPending else { return }
            completeActivationHandoff()
        }
    }

    private func cancelActivationHandoff() {
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
        )
        activationHandoffPID = nil
        isActivationHandoffPending = false
    }

    private func completeActivationHandoff() {
        cancelActivationHandoff()
        guard previousActivationPolicy != nil else { return }
        NSApp.activate(ignoringOtherApps: true)
        if let aboutWindow, aboutWindow.isVisible {
            aboutWindow.makeKeyAndOrderFront(nil)
        } else if isSettingsOpen {
            window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func windowWillClose(_: Notification) {
        isSettingsOpen = false
        finishPresentationIfPossible()
    }

    private func finishPresentationIfPossible() {
        guard !isSettingsOpen, aboutWindow == nil else { return }
        cancelActivationHandoff()
        NSApp.mainMenu = previousMenu
        if let previousActivationPolicy {
            NSApp.setActivationPolicy(previousActivationPolicy)
        }
        previousMenu = nil
        previousActivationPolicy = nil
    }

    @objc private func showAbout() {
        beginPresentation()
        NSApp.orderFrontStandardAboutPanel(options: [:])
        guard let panel = NSApp.keyWindow, panel !== window else { return }
        if let aboutWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: aboutWindow)
        }
        aboutWindow = panel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(aboutWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: panel,
        )
    }

    @objc private func aboutWindowWillClose(_: Notification) {
        aboutWindow = nil
        finishPresentationIfPossible()
    }

    #if !SANDBOX
        @objc private func openReleases() {
            NSWorkspace.shared.open(URL(string: "https://github.com/dannystewart/volumeHUD/releases/latest")!)
        }
    #endif

    @objc private func quit() {
        onQuit()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let applicationMenu = NSMenu(title: "volumeHUD")
        let aboutItem = applicationMenu.addItem(withTitle: "About volumeHUD", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        #if !SANDBOX
            let updateItem = applicationMenu.addItem(withTitle: "Update available!", action: #selector(openReleases), keyEquivalent: "")
            updateItem.target = self
            updateItem.isHidden = true
            self.updateItem = updateItem
        #endif
        applicationMenu.addItem(.separator())
        let settingsItem = applicationMenu.addItem(withTitle: "Settings…", action: #selector(open), keyEquivalent: ",")
        settingsItem.target = self
        applicationMenu.addItem(.separator())
        let quitItem = applicationMenu.addItem(withTitle: "Quit volumeHUD", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        return menu
    }
}

// MARK: - SettingsWindowConnection

private struct SettingsWindowConnection: NSViewRepresentable {
    final class ConnectionView: NSView {
        weak var controller: SettingsWindowController?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { controller?.attach(to: window) }
        }
    }

    let controller: SettingsWindowController

    func makeNSView(context _: Context) -> ConnectionView {
        let view = ConnectionView()
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: ConnectionView, context _: Context) {
        nsView.controller = controller
        if let window = nsView.window { controller.attach(to: window) }
    }
}
