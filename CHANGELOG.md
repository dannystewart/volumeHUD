# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog], and this project adheres to [Semantic Versioning].

## [1.2.5] (2025-09-28)

### Added

- Adds linting and VS Code workspace configurations.

### Changed

- Updates `polykit-swift` dependency to the latest revision for recent improvements and fixes, as well as

### Fixed

- Fixes a crash caused by a threading issue in volume monitoring by ensuring proper main queue dispatch for audio device changes.

## [1.2.4] (2025-09-26)

### Added

- Adopts Apple generic versioning to standardize build versions.

### Changed

- Upgrades Swift version from 5.0 to 6.0 to leverage newer language features, performance improvements, and enhanced concurrency support.
- Migrates `PolyLog` dependency from local package reference to my new `polykit-swift` library on GitHub for proper dependency management.
- Simplifies `PolyLog` initialization by removing conditional import workarounds and using direct instantiation now that it's working correctly.
- Improves user notification messages to be more friendly and informative with clearer success messaging.

### Fixed

- Improves display monitoring robustness with comprehensive change detection, fallback timer mechanism for positioning issues, and enhanced observer cleanup to prevent memory leaks.
- Fixes thread safety issues in HUD cleanup operations by ensuring UI-related cleanup occurs on the main thread.
- Fixes potential threading issues in display configuration change handlers by executing on the main actor.

## [1.2.3] (2025-09-23)

### Added

- Adds automatic HUD repositioning when display configuration changes in multi-monitor setups.
- Adds structured logging framework to improve debugging capabilities and log management.

### Changed

- Updates dependency URL format from SSH to HTTPS for better accessibility.
- Simplifies and improves README content with clearer installation instructions and feature descriptions.

### Fixed

- Fixes conditional import handling for PolyLog dependency with fallback when unavailable.
- Fixes redundant UI updates by tracking state changes and only updating when volume or mute status actually changes.
- Fixes volume key event handling with proper key code parsing and improved event monitoring cleanup.

### Removed

- Removes obsolete test UI interface file from early development.

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
- Adds Homebrew installation option as alternative to manual download.
- Adds VS Code workspace configuration for development environment.

### Changed

- Changes startup notification to only appear on first run instead of every app launch.
- Improves startup notification by including quit instructions.
- Improves accessibility permission error messages to be more user-friendly and accurate.
- Improves documentation clarity around notification behavior and usage.

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
[1.2.5]: https://github.com/dannystewart/volumeHUD/compare/v1.2.4...v1.2.5
[1.2.4]: https://github.com/dannystewart/volumeHUD/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/dannystewart/volumeHUD/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/dannystewart/volumeHUD/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/dannystewart/volumeHUD/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/dannystewart/volumeHUD/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/dannystewart/volumeHUD/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/dannystewart/volumeHUD/releases/tag/v1.0...v1.0.1
[1.0]: https://github.com/dannystewart/volumeHUD/releases/tag/v1.0
