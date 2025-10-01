# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog], and this project adheres to [Semantic Versioning].

## 2.0.0 (Unreleased)

### Added

- Adds brightness monitoring and unified HUD display for both volume and brightness changes. The brightness HUD should appear only for user-initiated changes and not automatic adjustments like ambient light change or dimming while on battery power.
- Adds a new About window with a proper "Quit volumeHUD" button.
- Adds a simple automatic update check using the GitHub API, showing a small link on the About screen when an update is available.

### Changed

- Sets the app to run as a background agent without appearing in the Dock. This should also avoid having it briefly brought to the foreground and stealing window focus on launch.
- Changes notification behavior. A notification now appears on every launch, but only when started manually and not as a login item. In practice, I found the lack of notification on startup to be confusing. The app likely isn't being restarted often enough for this to become annoying, and my main concern was avoiding a notification when launching automatically on startup.

### Removed

- Removes app sandbox restrictions to enable brightness functionality. I tried to avoid this, but reliable brightness detection was harder than volume without using private frameworks.
- Removes the quit-on-relaunch behavior, now showing the About box on relaunch instead. Also removes the notification when quitting, since it's now clear and explicit.

### Known Issues

- The brightness HUD currently only supports built-in displays. Considering the app was only intended for volume originally, brightness is kind of a bonus feature. Supporting external displays seems like a nightmare with DDC/CI variability, private APIs, event handling, supporting random USB/Thunderbolt docks, etc. If you'd like to help, PRs are welcome!

## [1.2.6] (2025-09-28)

### Changed

- Replaces event-based listeners with direct polling for audio device changes. This should be much more reliable and significantly reduce the risk of thread-based crashes when changing output device.

## [1.2.5] (2025-09-28)

### Fixed

- Fixes a crash caused by a threading issue in volume monitoring by ensuring proper main queue dispatch for audio device changes.

## [1.2.4] (2025-09-26)

### Changed

- Upgrades Swift version from 5.0 to 6.0 for newer language features and enhanced concurrency.
- Improves user notification messages to be more friendly and informative with clearer success messaging.

### Fixed

- Improves display monitoring robustness with comprehensive change detection, fallback timer mechanism for positioning issues, and enhanced observer cleanup to prevent memory leaks.
- Fixes thread safety issues in HUD cleanup operations by ensuring UI-related cleanup occurs on the main thread.
- Fixes potential threading issues in display configuration change handlers by executing on the main actor.

## [1.2.3] (2025-09-23)

### Added

- Adds automatic HUD repositioning when display configuration changes in multi-monitor setups.
- Adds structured logging framework to improve debugging capabilities and log management.

### Fixed

- Fixes redundant UI updates by tracking state changes and only updating when volume or mute status actually changes.
- Fixes volume key event handling with proper key code parsing and improved event monitoring cleanup.

## [1.2.2] (2025-09-22)

### Changed

- Simplifies volume key detection by removing redundant HID monitoring fallback code that was nonfunctional in sandboxed apps anyway.

### Fixed

- Fixes the HUD incorrectly triggering from non-volume media keys by restricting key detection to only activate at 0% and 100% volume boundaries and relying solely on volume change detection otherwise.

## [1.2.1] (2025-09-22)

### Fixed

- Fixes an issue where the app would no longer update the volume HUD after changing audio output devices.

## [1.2.0] (2025-09-21)

### Added

- Adds volume key detection when audio is at minimum or maximum levels, enabling HUD display even when system blocks volume changes.

### Changed

- Changes startup notification to only appear on first run instead of every app launch.
- Improves startup notification by including quit instructions.
- Improves accessibility permission error messages to be more user-friendly and accurate.

### Fixed

- Fixes quit notification text to use past tense ("volumeHUD quit" instead of "Quitting volumeHUD").

## [1.1.0] (2025-09-21)

### Added

- Adds toggle functionality where launching the app again terminates the running instance.
- Adds user notifications to inform users when the app starts and stops.

## [1.0.1] (2025-09-21)

### Changed

- Adjusted the icon change thresholds. Previously used an equal 25/50/75 split, which kept the silent icon for too long. Now it's only used for the first increment, with a balanced 33/66 split for the rest.

## [1.0] (2025-09-21)

Initial release.

<!-- Links -->
[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html

<!-- Versions -->
[1.2.6]: https://github.com/dannystewart/volumeHUD/compare/v1.2.5...v1.2.6
[1.2.5]: https://github.com/dannystewart/volumeHUD/compare/v1.2.4...v1.2.5
[1.2.4]: https://github.com/dannystewart/volumeHUD/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/dannystewart/volumeHUD/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/dannystewart/volumeHUD/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/dannystewart/volumeHUD/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/dannystewart/volumeHUD/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/dannystewart/volumeHUD/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/dannystewart/volumeHUD/releases/tag/v1.0...v1.0.1
[1.0]: https://github.com/dannystewart/volumeHUD/releases/tag/v1.0
