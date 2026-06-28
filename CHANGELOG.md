# Changelog

## 0.1.4

- Added `fdev ios` for flavor-based iOS builds (macOS only).
- Added `fdev icons` for launcher icon generation via flutter_launcher_icons.
- Added `fdev splash` for native splash screen generation via flutter_native_splash.
- Added `fdev env` for selecting dev/stage/prod `.env` files into `.env`.
- Added `fdev release-notes` for APK metadata and changelog output.
- Added `fdev swagger --watch` to regenerate models when a local Swagger file changes.
- Fixed `CliFailure` exceptions from subcommand handlers escaping the top-level
  try/catch by awaiting handler invocations.

## 0.1.3

- Renamed package to `fdev` for a shorter, cleaner name on pub.dev.
- Added detailed OS-specific setup guides and a feature compatibility matrix to the README.
- Enhanced subprocess handling for Windows shell execution compatibility.
- Implemented macOS checks for iOS CocoaPods commands.

## 0.1.2

- Updated `fdev swagger` model generation to honor Swagger/OpenAPI `required`
  and nullable field metadata.

## 0.1.1

- Added `fdev clean` for `flutter clean` followed by `flutter pub get`.

## 0.1.0

- Added `fdev doctor`.
- Added `fdev gen` for build_runner.
- Added `fdev apk` for flavor-aware APK builds.
- Added `fdev swagger` for Swagger/OpenAPI model generation.
