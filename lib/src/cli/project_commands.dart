part of '../cli.dart';

Future<int> _doctor(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printDoctorHelp();
    return 0;
  }

  stdout.writeln('fdev doctor');
  stdout.writeln('cwd: ${Directory.current.path}');
  stdout.writeln(
    'flutter project: ${File('pubspec.yaml').existsSync() ? 'yes' : 'no'}',
  );
  stdout.writeln('');

  await _printVersion('dart', ['--version']);
  await _printVersion('flutter', ['--version']);

  stdout.writeln('fdev version: $cliVersion');
  final latest = await _fetchLatestVersion();
  _checkAndPrintUpdate(cliVersion, latest);

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stdout.writeln('');
    stdout.writeln(
      'No pubspec.yaml in this folder. Run Flutter commands from a Flutter project root.',
    );
  }

  return 0;
}

Future<int> _buildRunner(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printBuildRunnerHelp();
    return 0;
  }

  _ensurePubspec();

  final parsed = ParsedArgs.parse(
    args,
    optionNames: const {'mode'},
    aliases: const {},
  );

  final watch = parsed.hasFlag('watch');
  final noDelete = parsed.hasFlag('no-delete-conflicting');
  final mode = parsed.option('mode');
  final subCommand = watch || mode == 'watch' ? 'watch' : 'build';

  final command = <String>[
    'run',
    'build_runner',
    subCommand,
    if (!noDelete) '--delete-conflicting-outputs',
    ...parsed.passthrough,
  ];

  stdout.writeln('Running: dart ${command.join(' ')}');
  return _runInherited('dart', command);
}

Future<int> _clean(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printCleanHelp();
    return 0;
  }
  if (args.isNotEmpty) {
    throw const CliFailure('Usage: fdev clean');
  }

  _ensurePubspec();

  var exitCode = await _runStep('flutter', const ['clean']);
  if (exitCode != 0) {
    return exitCode;
  }

  exitCode = await _runStep('flutter', const ['pub', 'get']);
  return exitCode;
}

Future<int> _buildApk(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printApkHelp();
    return 0;
  }

  return _buildFlutterArtifact(
    args,
    artifact: 'apk',
    supportedFlags: const {'split-per-abi'},
  );
}

Future<int> _buildAppBundle(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printAppBundleHelp();
    return 0;
  }

  return _buildFlutterArtifact(args, artifact: 'appbundle');
}

Future<int> _buildFlutterArtifact(
  List<String> args, {
  required String artifact,
  Set<String> supportedFlags = const {},
}) async {
  _ensurePubspec();

  final parsed = ParsedArgs.parse(
    args,
    optionNames: const {
      'flavor',
      'target',
      'mode',
      'build-name',
      'build-number',
      'dart-define',
    },
    aliases: const {'f': 'flavor', 't': 'target'},
    repeatableOptions: const {'dart-define'},
  );

  final flavor = parsed.option('flavor') ??
      (parsed.positionals.isNotEmpty ? parsed.positionals.first : null);
  final target = parsed.option('target');
  final mode = _resolveBuildMode(parsed, artifact: artifact);

  final command = <String>[
    'build',
    artifact,
    '--$mode',
    if (flavor != null && flavor.isNotEmpty) ...['--flavor', flavor],
    if (target != null && target.isNotEmpty) ...['-t', target],
    if (supportedFlags.contains('split-per-abi') &&
        parsed.hasFlag('split-per-abi'))
      '--split-per-abi',
    for (final value in parsed.options['dart-define'] ?? const <String>[])
      '--dart-define=$value',
    if (parsed.option('build-name') case final buildName?)
      '--build-name=$buildName',
    if (parsed.option('build-number') case final buildNumber?)
      '--build-number=$buildNumber',
    ...parsed.passthrough,
  ];

  stdout.writeln('Running: flutter ${command.join(' ')}');
  return _runInherited('flutter', command);
}

Future<int> _buildIos(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printIosHelp();
    return 0;
  }

  if (!Platform.isMacOS) {
    throw const CliFailure('iOS builds require macOS with Xcode installed.');
  }

  if (!Directory('ios').existsSync()) {
    throw const CliFailure(
      'No ios directory found. Run this command from a Flutter project root '
      'after adding the iOS platform with `flutter create .`.',
    );
  }

  return _buildFlutterArtifact(args, artifact: 'ios');
}

void _ensureDevDependency(
  String packageName, {
  required String installHint,
}) {
  final content = File('pubspec.yaml').readAsStringSync();
  // Match an uncommented "package_name:" key anywhere in the file.
  final present = RegExp(
    r'^[^#\n]*' + RegExp.escape(packageName) + r'\s*:',
    multiLine: true,
  ).hasMatch(content);
  if (!present) {
    stdout.writeln(
      'Note: "$packageName" was not found in pubspec.yaml. '
      'If this fails, add it with: $installHint',
    );
  }
}

Future<int> _launcherIcons(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printLauncherIconsHelp();
    return 0;
  }

  _ensurePubspec();

  _ensureDevDependency(
    'flutter_launcher_icons',
    installHint: 'dart pub add dev:flutter_launcher_icons',
  );

  final parsed = ParsedArgs.parse(
    args,
    optionNames: const {'file', 'prefix'},
    aliases: const {'f': 'file', 'p': 'prefix'},
  );

  final command = <String>[
    'run',
    'flutter_launcher_icons',
    if (parsed.option('file') case final file?) ...['-f', file],
    if (parsed.option('prefix') case final prefix?) ...['-p', prefix],
    if (parsed.hasFlag('verbose')) '-v',
    ...parsed.passthrough,
  ];

  stdout.writeln('Running: dart ${command.join(' ')}');
  return _runInherited('dart', command);
}

Future<int> _nativeSplash(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printNativeSplashHelp();
    return 0;
  }

  _ensurePubspec();

  _ensureDevDependency(
    'flutter_native_splash',
    installHint: 'dart pub add dev:flutter_native_splash',
  );

  final parsed = ParsedArgs.parse(
    args,
    optionNames: const {'path', 'flavor'},
    aliases: const {'p': 'path', 'f': 'flavor'},
  );

  final script = parsed.hasFlag('remove') ? 'remove' : 'create';
  final command = <String>[
    'run',
    'flutter_native_splash:$script',
    if (parsed.option('path') case final path?) ...['-p', path],
    if (parsed.option('flavor') case final flavor?) ...['-f', flavor],
    ...parsed.passthrough,
  ];

  stdout.writeln('Running: dart ${command.join(' ')}');
  return _runInherited('dart', command);
}

List<String> _candidateEnvFiles(String environment) {
  return [
    '.env.$environment',
    '.env_$environment',
    'env/.env.$environment',
    'envs/$environment.env',
    'config/.env.$environment',
  ];
}

List<String> _envDefines(String envContent) {
  final defines = <String>[];
  for (final rawLine in envContent.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (!line.contains('=')) continue;
    final eq = line.indexOf('=');
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    // Strip surrounding quotes from the value.
    final unquoted = value.replaceAll(RegExp(r'''^["']|["']$'''), '');
    if (key.isNotEmpty) {
      defines.add('$key=$unquoted');
    }
  }
  return defines;
}

Future<int> _env(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printEnvHelp();
    return 0;
  }

  _ensurePubspec();

  final parsed = ParsedArgs.parse(
    args,
    optionNames: const {'out'},
    aliases: const {'o': 'out'},
  );

  if (parsed.hasFlag('list')) {
    final envs = _listAvailableEnvironments();
    if (envs.isEmpty) {
      stdout.writeln('No .env.* files found in this project.');
    } else {
      stdout.writeln('Available environments:');
      for (final env in envs) {
        stdout.writeln('  $env');
      }
    }
    return 0;
  }

  final environment = parsed.positionals.isNotEmpty
      ? parsed.positionals.first
      : _promptWithDefault('Environment (dev/stage/prod)', 'dev');

  File? sourceFile;
  for (final candidate in _candidateEnvFiles(environment)) {
    final file = File(candidate);
    if (file.existsSync()) {
      sourceFile = file;
      break;
    }
  }
  if (sourceFile == null) {
    throw CliFailure(
      'No environment file found for "$environment". '
      'Looked for: ${_candidateEnvFiles(environment).join(', ')}.',
    );
  }

  final content = await sourceFile.readAsString();
  final outPath = parsed.option('out') ?? '.env';
  await File(outPath).writeAsString(content);
  stdout.writeln('Wrote $outPath from ${sourceFile.path}');

  if (parsed.hasFlag('flutter-define')) {
    final defines = _envDefines(content);
    if (defines.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('dart-define flags:');
      for (final define in defines) {
        stdout.writeln('  --dart-define=$define');
      }
    }
  }

  return 0;
}

List<String> _listAvailableEnvironments() {
  final envs = <String>{};
  for (final entity in Directory.current.listSync()) {
    if (entity is! File) continue;
    final name = _fileName(entity.path);
    final match = RegExp(r'^\.env\.([A-Za-z0-9_-]+)$').firstMatch(name);
    if (match != null) {
      envs.add(match.group(1)!);
    }
  }
  final sorted = envs.toList()..sort();
  return sorted;
}

({String name, String? buildNumber}) _readPubspecVersion() {
  final content = File('pubspec.yaml').readAsStringSync();
  final match =
      RegExp(r'^version:\s*(.+?)\s*$', multiLine: true).firstMatch(content);
  if (match == null) {
    throw const CliFailure(
      'Could not find a `version:` field in pubspec.yaml.',
    );
  }
  final raw = match.group(1)!.trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
  final plusIndex = raw.indexOf('+');
  if (plusIndex == -1) {
    return (name: raw, buildNumber: null);
  }
  return (
    name: raw.substring(0, plusIndex),
    buildNumber: raw.substring(plusIndex + 1),
  );
}

Future<String?> _readReleaseNotesFile() async {
  for (final name in [
    'RELEASE_NOTES.md',
    'release_notes.txt',
    'RELEASE_NOTES.txt',
  ]) {
    final file = File(name);
    if (file.existsSync()) {
      return await file.readAsString();
    }
  }
  return null;
}

Future<int> _releaseNotes(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printReleaseNotesHelp();
    return 0;
  }

  _ensurePubspec();

  final parsed = ParsedArgs.parse(
    args,
    optionNames: const {'out', 'notes', 'version', 'build-number'},
    aliases: const {'o': 'out'},
  );

  final pubspecVersion = _readPubspecVersion();
  final versionName = parsed.option('version') ?? pubspecVersion.name;
  final buildNumber =
      parsed.option('build-number') ?? pubspecVersion.buildNumber ?? '1';

  final notes = parsed.option('notes') ??
      await _readReleaseNotesFile() ??
      'Release $versionName';

  final outDir = parsed.option('out') ?? 'fastlane/metadata/android/en-US';
  final changelogDir = Directory('$outDir/changelogs');
  await changelogDir.create(recursive: true);

  final changelogFile = File('${changelogDir.path}/$buildNumber.txt');
  await changelogFile.writeAsString(notes);

  stdout.writeln('Version: $versionName');
  stdout.writeln('Build number: $buildNumber');
  stdout.writeln('Changelog: ${changelogFile.path}');
  return 0;
}
