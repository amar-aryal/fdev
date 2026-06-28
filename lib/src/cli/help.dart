part of '../cli.dart';

void _printHelp() {
  stdout.writeln(r'''
fdev - local Flutter developer CLI

Usage:
  fdev <command> [options]

Commands:
  doctor                 Check Dart/Flutter availability.
  gen                    Run build_runner with --delete-conflicting-outputs.
  clean                  Run flutter clean, then flutter pub get.
  apk                    Build a Flutter APK, with optional flavor/target.
  appbundle              Build a Flutter Android app bundle.
  ios                    Build a Flutter iOS app, with optional flavor/target.
  icons                  Generate launcher icons via flutter_launcher_icons.
  splash                 Generate native splash screens via flutter_native_splash.
  env                    Select dev/stage/prod .env files into .env.
  release-notes          Write APK metadata and changelog from pubspec version.
  pod update             Run flutter clean, flutter pub get, then pod update.
  signapk                Generate android/app keystore.jks and properties.
  sha                    Show SHA1 and SHA256 for an existing Android keystore.
  swagger                Generate Dart API response models from Swagger/OpenAPI JSON.
  upgrade                Upgrade fdev to the latest version from pub.dev.
  version                Print the current version of fdev.

Examples:
  fdev gen
  fdev gen --watch
  fdev clean
  fdev apk --flavor dev --target lib/main_dev.dart
  fdev apk dev -t lib/main_dev.dart --split-per-abi
  fdev appbundle dev -t lib/main_dev.dart
  fdev ios dev -t lib/main_dev.dart
  fdev icons -f flutter_launcher_icons.yaml
  fdev splash --flavor dev
  fdev env stage
  fdev release-notes --notes "Fix login bug"
  fdev pod update
  fdev signapk
  fdev sha
  fdev swagger --url https://example.com/swagger.json --out lib/models/api_models.dart
  fdev swagger --file swagger.json --watch
  fdev upgrade
  fdev version

Run `fdev <command> --help` for command-specific options.
''');
}

void _printDoctorHelp() {
  stdout.writeln(r'''
Usage:
  fdev doctor

Checks the current folder and prints local Dart/Flutter versions.
''');
}

void _printBuildRunnerHelp() {
  stdout.writeln(r'''
Usage:
  fdev gen [options] [-- extra build_runner args]

Options:
  --watch                    Run `build_runner watch`.
  --mode watch               Same as --watch.
  --no-delete-conflicting    Do not pass --delete-conflicting-outputs.

Examples:
  fdev gen
  fdev gen --watch
  fdev gen -- --build-filter="lib/**"
''');
}

void _printCleanHelp() {
  stdout.writeln(r'''
Usage:
  fdev clean

Runs these commands from a Flutter project root:
  flutter clean
  flutter pub get
''');
}

void _printApkHelp() {
  stdout.writeln(r'''
Usage:
  fdev apk [flavor] [options] [-- extra flutter build args]

Options:
  -f, --flavor <name>        Flutter flavor name.
  -t, --target <path>        Dart entrypoint, for example lib/main_dev.dart.
  --mode <mode>              release, debug, or profile. Default: release.
  --release                  Build release APK. Default.
  --debug                    Build debug APK.
  --profile                  Build profile APK.
  --split-per-abi            Pass --split-per-abi.
  --dart-define <KEY=VALUE>  Can be passed multiple times.
  --build-name <value>       Flutter build name.
  --build-number <value>     Flutter build number.

Examples:
  fdev apk dev
  fdev apk --flavor dev --target lib/main_dev.dart
  fdev apk prod -t lib/main_prod.dart --split-per-abi
''');
}

void _printAppBundleHelp() {
  stdout.writeln(r'''
Usage:
  fdev appbundle [flavor] [options] [-- extra flutter build args]

Options:
  -f, --flavor <name>        Flutter flavor name.
  -t, --target <path>        Dart entrypoint, for example lib/main_dev.dart.
  --mode <mode>              release, debug, or profile. Default: release.
  --release                  Build release app bundle. Default.
  --debug                    Build debug app bundle.
  --profile                  Build profile app bundle.
  --dart-define <KEY=VALUE>  Can be passed multiple times.
  --build-name <value>       Flutter build name.
  --build-number <value>     Flutter build number.

Examples:
  fdev appbundle dev
  fdev appbundle --flavor dev --target lib/main_dev.dart
  fdev appbundle prod -t lib/main_prod.dart --dart-define API_ENV=prod
''');
}

void _printIosHelp() {
  stdout.writeln(r'''
Usage:
  fdev ios [flavor] [options] [-- extra flutter build args]

Options:
  -f, --flavor <name>        Flutter flavor name.
  -t, --target <path>        Dart entrypoint, for example lib/main_dev.dart.
  --mode <mode>              release, debug, or profile. Default: release.
  --release                  Build release iOS app. Default.
  --debug                    Build debug iOS app.
  --profile                  Build profile iOS app.
  --dart-define <KEY=VALUE>  Can be passed multiple times.
  --build-name <value>       Flutter build name.
  --build-number <value>     Flutter build number.

Examples:
  fdev ios dev
  fdev ios --flavor dev --target lib/main_dev.dart
  fdev ios prod -t lib/main_prod.dart

Note: iOS builds require macOS with Xcode installed.
''');
}

void _printLauncherIconsHelp() {
  stdout.writeln(r'''
Usage:
  fdev icons [options]

Generates launcher icons by running flutter_launcher_icons from pubspec.yaml
or a custom config file.

Options:
  -f, --file <path>     Config file. Default: flutter_launcher_icons.yaml, then pubspec.yaml.
  -p, --prefix <path>   Output prefix path (web only).
  --verbose             Verbose output.

Examples:
  fdev icons
  fdev icons -f flutter_launcher_icons.yaml
''');
}

void _printNativeSplashHelp() {
  stdout.writeln(r'''
Usage:
  fdev splash [options]

Generates native splash screens by running flutter_native_splash from
flutter_native_splash.yaml or pubspec.yaml.

Options:
  -p, --path <path>     Path to the Flutter project root.
  -f, --flavor <name>   Flavor to create the splash for.
  --remove              Remove the splash and restore defaults.

Examples:
  fdev splash
  fdev splash --flavor dev
  fdev splash --remove --flavor dev
''');
}

void _printEnvHelp() {
  stdout.writeln(r'''
Usage:
  fdev env <environment> [options]

Writes the matching .env.<environment> (or .env_<environment>) file to .env.

Options:
  -o, --out <path>        Output file. Default: .env.
  --list                  List available environments and exit.
  --flutter-define        Print --dart-define flags for the selected env.

Examples:
  fdev env dev
  fdev env stage -o .env
  fdev env prod --flutter-define
  fdev env --list
''');
}

void _printReleaseNotesHelp() {
  stdout.writeln(r'''
Usage:
  fdev release-notes [options]

Writes fastlane-style APK metadata and a changelog from the pubspec version.

Options:
  -o, --out <dir>            Output metadata directory.
                             Default: fastlane/metadata/android/en-US.
  --notes <text>             Release notes text. Default: RELEASE_NOTES.md or "Release <version>".
  --version <value>          Override the pubspec version name.
  --build-number <value>     Override the pubspec build number.

Examples:
  fdev release-notes --notes "Fix login bug"
  fdev release-notes --version 1.2.3 --build-number 4
''');
}

void _printPodUpdateHelp() {
  stdout.writeln(r'''
Usage:
  fdev pod update [extra pod update args]
  fdev pod-update [extra pod update args]

Runs these commands from a Flutter project root:
  flutter clean
  flutter pub get
  cd ios && pod update

Examples:
  fdev pod update
  fdev pod-update --repo-update
''');
}

void _printSignApkHelp() {
  stdout.writeln(r'''
Usage:
  fdev signapk [options]

Generates an Android upload keystore and properties file:
  android/app/keystore.jks
  android/app/keystore.properties

Options:
  -f, --file <name>         Keystore file name. Default: keystore.jks.
  -a, --alias <name>        Key alias. Default: upload.
  --validity <days>         Certificate validity. Default: 10000.
  --dname <value>           Full keytool distinguished name.

The command asks for passwords, creates both files, then prints SHA1 and SHA256.

Examples:
  fdev signapk
  fdev signapk --file upload-keystore.jks --alias upload
''');
}

void _printKeystoreShaHelp() {
  stdout.writeln(r'''
Usage:
  fdev sha [options]
  fdev keystore-sha [options]

Shows SHA1 and SHA256 for an Android keystore.

Options:
  -f, --file <path-or-name>  JKS file path or file name in android/app.
  -a, --alias <name>        Key alias. Default: keyAlias from properties or upload.

If android/app/keystore.properties exists, fdev can reuse storeFile, keyAlias,
and storePassword from that file.

Examples:
  fdev sha
  fdev sha --file keystore.jks
  fdev keystore-sha --file android/app/upload-keystore.jks --alias upload
''');
}

void _printSwaggerHelp() {
  stdout.writeln(r'''
Usage:
  fdev swagger [options]

Options:
  -u, --url <url>            Swagger/OpenAPI JSON URL. If omitted, fdev prompts.
  --file <path>              Read Swagger/OpenAPI JSON from a local file.
  -o, --out <path>           Output Dart file. Default: lib/models/api_models.dart.
  --root <name>              Root class name when input is sample JSON. Default: ApiResponse.
  --class-prefix <prefix>    Prefix generated class names.
  --watch                    Watch --file and regenerate on change (requires --file).
  --interval <seconds>       Poll interval for --watch. Default: 2.

Examples:
  fdev swagger --url https://example.com/swagger.json
  fdev swagger --file swagger.json --out lib/data/models/api_models.dart
  fdev swagger --file swagger.json --watch
  fdev swagger --file swagger.json --watch --interval 1
''');
}
