# fdev

[![pub package](https://img.shields.io/pub/v/fdev.svg)](https://pub.dev/packages/fdev)

`fdev` is a local Dart CLI for repeated Flutter development tasks:

- run `build_runner` with `--delete-conflicting-outputs`
- run `flutter clean` followed by `flutter pub get`
- build APKs with flavor, target, build mode, defines, and split ABI flags
- build Android app bundles with flavor, target, build mode, and defines
- run the iOS pod update workflow
- generate Android upload keystores and show SHA fingerprints
- generate plain Dart API response models from Swagger/OpenAPI JSON
- check local Dart/Flutter setup

This package is intentionally dependency-free. The generated API models also avoid external dependencies and include manual `fromJson` and `toJson` methods.

## Installation

You can install `fdev` globally from [pub.dev](https://pub.dev) using the Dart SDK:

```sh
dart pub global activate fdev
```

### OS-Specific Path Setup

To run `fdev` from any terminal, Dart's global bin directory must be added to your system's PATH:

| Operating System | Path to Add | How to Configure |
| :--- | :--- | :--- |
| **macOS / Linux** | `$HOME/.pub-cache/bin` | Add `export PATH="$PATH:$HOME/.pub-cache/bin"` to `~/.zshrc` or `~/.bashrc` and run `source ~/.zshrc`. |
| **Windows** | `%USERPROFILE%\.pub-cache\bin`<br>or `%APPDATA%\Pub\Cache\bin` | Add the path to your User Environment Variables under `Path` using the System Settings GUI. |

Verify the installation:

```sh
fdev version
fdev doctor
```

### OS Compatibility Table

Here is the compatibility matrix for `fdev` features across operating systems:

| Feature / Command | macOS | Windows | Linux | Note |
| :--- | :---: | :---: | :---: | :--- |
| **`fdev doctor`** | ✅ | ✅ | ✅ | Check Dart/Flutter/fdev environment |
| **`fdev gen`** | ✅ | ✅ | ✅ | Run `build_runner` code generator |
| **`fdev clean`** | ✅ | ✅ | ✅ | Clean project build cache & fetch packages |
| **`fdev apk`** | ✅ | ✅ | ✅ | Android APK builds |
| **`fdev appbundle`** | ✅ | ✅ | ✅ | Android App Bundle builds |
| **`fdev signapk`** | ✅ | ✅ | ✅ | Generate Android signing keys |
| **`fdev sha`** | ✅ | ✅ | ✅ | Show keystore SHA fingerprints |
| **`fdev swagger`** | ✅ | ✅ | ✅ | Swagger/OpenAPI model generator |
| **`fdev upgrade`** | ✅ | ✅ | ✅ | Self-upgrade CLI to the latest version |
| **`fdev version`** | ✅ | ✅ | ✅ | Print active CLI version |
| **`fdev pod update`** | ✅ | ❌ | ❌ | CocoaPods is macOS-only |

### Local Development / Activation

If you are developing this tool locally on this laptop, navigate to the project directory and run:

```sh
dart pub global activate --source path .
```

## Commands

### Run Build Runner

From a Flutter project root:

```sh
fdev gen
```

This runs:

```sh
dart run build_runner build --delete-conflicting-outputs
```

Watch mode:

```sh
fdev gen --watch
```

Pass extra arguments after `--`:

```sh
fdev gen -- --build-filter="lib/**"
```

### Clean And Get Packages

From a Flutter project root:

```sh
fdev clean
```

This runs:

```sh
flutter clean
flutter pub get
```

### Build APK

Default release build:

```sh
fdev apk
```

With flavor:

```sh
fdev apk dev
```

With flavor and target:

```sh
fdev apk --flavor dev --target lib/main_dev.dart
```

With split ABI and defines:

```sh
fdev apk prod -t lib/main_prod.dart --split-per-abi --dart-define API_ENV=prod
```

Debug/profile:

```sh
fdev apk dev --debug
fdev apk dev --profile
```

### Build App Bundle

Default release build:

```sh
fdev appbundle
```

With flavor and target:

```sh
fdev appbundle --flavor dev --target lib/main_dev.dart
```

With defines:

```sh
fdev appbundle prod -t lib/main_prod.dart --dart-define API_ENV=prod
```

Debug/profile:

```sh
fdev appbundle dev --debug
fdev appbundle dev --profile
```

### Update iOS Pods

From a Flutter project root:

```sh
fdev pod update
```

This runs:

```sh
flutter clean
flutter pub get
cd ios && pod update
```

The short alias also works:

```sh
fdev pod-update
```

### Generate Android Signing Keystore

From a Flutter project root:

```sh
fdev signapk
```

The CLI asks for:

- JKS file name
- key alias
- store password
- key password
- certificate owner name

It creates:

```text
android/app/keystore.jks
android/app/keystore.properties
```

Then it prints SHA1 and SHA256.

Custom file and alias:

```sh
fdev signapk --file upload-keystore.jks --alias upload
```

The generated `keystore.properties` contains:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=keystore.jks
```

Keep the keystore and signing passwords private.

### Show Android Keystore SHA

From a Flutter project root:

```sh
fdev sha
```

The CLI asks for the JKS file name and prints SHA1/SHA256. If
`android/app/keystore.properties` exists, it reuses the stored file name, alias,
and password.

Non-interactive:

```sh
fdev sha --file keystore.jks
fdev keystore-sha --file android/app/upload-keystore.jks --alias upload
```

### Generate Models From Swagger

From a Flutter project root:

```sh
fdev swagger
```

The CLI asks for the Swagger/OpenAPI JSON URL and writes:

```text
lib/models/api_models.dart
```

Non-interactive:

```sh
fdev swagger --url https://example.com/swagger.json --out lib/data/models/api_models.dart
```

From a local JSON file:

```sh
fdev swagger --file swagger.json --out lib/data/models/api_models.dart
```

The generator reads:

- OpenAPI 3 `components.schemas`
- Swagger 2 `definitions`
- inline JSON response schemas under `paths`
- plain sample JSON objects when the input is not an OpenAPI document

Generated models follow the Swagger/OpenAPI contract:

- fields listed in a schema's `required` array become required constructor
  parameters
- required fields are non-nullable unless the property is marked nullable
- optional fields stay nullable because the response may omit them
- `nullable: true`, `x-nullable: true`, `type: ["...", "null"]`, and
  `oneOf`/`anyOf` null variants are treated as nullable

## Updating & Upgrading

### How to Upgrade

If you installed `fdev` from [pub.dev](https://pub.dev), you can easily update it to the latest version by running:

```sh
fdev upgrade
```

Alternatively, you can re-run the activation command:

```sh
dart pub global activate fdev
```

### Developing & Publishing Updates

1. **Modify Code**: Edit files under `lib/src/` or add new commands in `lib/src/cli.dart`.
2. **Version Bump**:
   - Update `version` in `pubspec.yaml`.
   - Update `cliVersion` in `lib/src/cli.dart`.
   - Document changes in `CHANGELOG.md`.
3. **Format & Analyze**:
   ```sh
   dart format .
   dart analyze
   ```
4. **Local Activation Test**:
   ```sh
   dart pub global activate --source path .
   ```
5. **Publish to pub.dev**:
   - Run dry-run checks:
     ```sh
     dart pub publish --dry-run
     ```
   - Publish to [pub.dev](https://pub.dev):
     ```sh
     dart pub publish
     ```

## Recommended Future Features

- `fdev ios` for flavor-based iOS builds
- `fdev icons` for launcher icon generation
- `fdev splash` for native splash generation
- `fdev env` for selecting dev/stage/prod `.env` files
- `fdev release-notes` for APK metadata and changelog output
- `fdev swagger --watch` to regenerate when a local Swagger file changes
