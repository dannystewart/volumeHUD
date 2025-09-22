# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog], and this project adheres to [Semantic Versioning].

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
[1.2.2]: https://github.com/dannystewart/volumeHUD/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/dannystewart/volumeHUD/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/dannystewart/volumeHUD/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/dannystewart/volumeHUD/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/dannystewart/volumeHUD/releases/tag/v1.0...v1.0.1
[1.0]: https://github.com/dannystewart/volumeHUD/releases/tag/v1.0
