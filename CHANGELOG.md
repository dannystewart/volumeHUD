# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog], and this project adheres to [Semantic Versioning].

## [Unreleased]

## [2.3.0] (2025-11-01)

### Added

- Adds relative HUD position setting, so people can choose between percentage-based distance from the bottom (the app's original behavior) and absolute pixel positioning (Apple's default behavior).

### Changed

- Replaces the About view layout with a new two-column design to make room for settings without feeling cramped.
- Reverts the change to absolute positioning by default and now uses relative positioning again (the pre-2.2.0 behavior). Apple-style absolute positioning is now optional via Settings.

### Fixed

- Fixes an issue with Option+Shift for brightness control where the keypress state persisted after keys were released. This caused brightness to detect changes in 1/64th increments which significantly increased false positives from ambient light changes and other external factors.

## [2.2.0] (2025-10-29)

### Added

- Adds fine-grained brightness and volume control by holding Option+Shift to adjust with 64-step precision, matching prior macOS behavior. (Thanks to  SamusAranX and claire9318054 for requesting this!)
- Adds a new app icon using Icon Composer, replacing the legacy asset catalog approach.

### Changed

- Adjusts HUD placement to ignore the Dock and menu bar for consistency, and repositions it to 140px from the bottom to match the prior macOS appearance. (Big thanks to SamusAranX for pointing out the inconsistencies here!)

### Fixed

- Fixes slight inconsistency in window dimensions between HUDController and HUDView. (No visual change.)
- Fixes HUD window level to prevent blocking system features like Exposé and Show Desktop while maintaining proper display hierarchy. (Thanks to usagimaru for reporting this!)

## [2.1.0] (2025-10-17)

### Added

- Adds a user preference for which screen the volume HUD should appear on.

### Changed

- Reverts the default HUD position back to the primary display (the pre-2.0.2 behavior), but now with an option so you can choose which you prefer.

## [2.0.2] (2025-10-05)

### Added

- The volume HUD now shows on the screen with the mouse cursor instead of always using the main display. The brightness HUD always shows on the built-in screen since that's what it controls.

## [2.0.1] (2025-10-05)

### Added

- Adds dual-tap monitoring system for improved brightness key detection reliability using both session-level and HID-level event monitoring.
- Adds automatic restart of event monitoring when display configuration changes are detected.

### Changed

- Improves display targeting by focusing on the *built-in* display rather than *main* display for consistent brightness control.
- Improves HUD positioning for multi-display setups by prioritizing the built-in display and respecting the menu bar and Dock areas.
- Increases display configuration change debounce from 100ms to 500ms for better handling of rapid changes during lid operations.

### Fixed

- Fixes potentially duplicated HUD displays by adding 50ms deduplication window when multiple event taps fire simultaneously.
- Fixes monitoring reliability by adding automatic recovery when event tap becomes disabled and removing early exit conditions that prevented recovery.

## [2.0.0] (2025-10-04)

### Added

- **Brightness:** The app now supports brightness! The brightness HUD is off by default (the app is volumeHUD, after all) but can be enabled from the new About window. It should only appear for user-initiated changes, not automatic triggers like ambient light or battery power.
- **Open at Login:** You can now set it to open at login from directly from the app.
- **Interface:** A new About window now provides controls for the brightness HUD and opening at login, as well as a proper quit button. Clicking the startup notification will now open the About window (as will relaunching the app).
- **Update Check:** Adds a simple automatic update check using the GitHub API, showing a small link on the About screen when an update is available. I hesitated to add network access, but it's just one anonymous call to GitHub, failing silently if it can't connect. No nag, no automatic download.

### Changed

- **Notifications:** Now notifies on startup rather than quit, but only when run manually (not as a login item). I've found it helpful to be sure you've launched an app that's otherwise transparent. Notifications remain completely optional.

### Fixed

- Now runs as a proper background agent, which should prevent it from temporarily appearing in the Dock or stealing window focus on launch.
- Detects when another instance of the app is already running from another location, preventing accidentally opening multiple copies at once.
- Fixes detection of Accessibility permissions. The app has always been designed to work without permissions but it turns out I was doing too good a job, as it always assumed it didn't have them and never asked. It should now request them properly on first launch. (See known issues below.)

### Removed

- Removes quit-on-relaunch behavior and the quit notification.
- Removes App Sandbox restrictions due to brightness functionality. I tried to avoid it, but brightness detection was too unreliable without private frameworks.

### Notes and Known Issues

- Brightness detection *may* be slightly less reliable than volume, especially for ambient light detection and switching to battery, but it should be accounting for all that. It's been working well for me with no issues, but should be considered experimental (another reason it's off by default).
- Brightness detection only supports built-in displays. Supporting external displays seems like a nightmare with DDC/CI variability, private APIs, event handling, supporting random USB/Thunderbolt docks, and other things that aren't fun. If you'd like to help, PRs are welcome!
- If you had the app installed previously and want to be able to use key presses to track volume and brightness when at min/max, you will likely have to grant it Accessibility permissions manually (or remove it from the list so it can ask properly).

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
[unreleased]: https://github.com/dannystewart/volumeHUD/compare/v2.3.0...HEAD
[2.3.0]: https://github.com/dannystewart/volumeHUD/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/dannystewart/volumeHUD/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/dannystewart/volumeHUD/compare/v2.0.2...v2.1.0
[2.0.2]: https://github.com/dannystewart/volumeHUD/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/dannystewart/volumeHUD/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/dannystewart/volumeHUD/compare/v1.2.6...v2.0.0
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
