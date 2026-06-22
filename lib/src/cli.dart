import 'dart:convert';
import 'dart:io';

import 'swagger_generator.dart';

class FdevExit implements Exception {
  const FdevExit(this.code);

  final int code;
}

class CliFailure implements Exception {
  const CliFailure(this.message, {this.exitCode = 64});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

Future<int> runFdev(List<String> args) async {
  try {
    if (args.isEmpty) {
      _printHelp();
      return 0;
    }

    final command = args.first;
    if (_isHelp(command)) {
      _printHelp();
      return 0;
    }
    if (_isVersion(command)) {
      await _printVersionInfo();
      return 0;
    }

    final rest = args.sublist(1);

    switch (command) {
      case 'doctor':
        return _doctor(rest);
      case 'gen':
      case 'runner':
      case 'build-runner':
        return _buildRunner(rest);
      case 'clean':
        return _clean(rest);
      case 'apk':
      case 'build-apk':
        return _buildApk(rest);
      case 'appbundle':
      case 'aab':
      case 'build-appbundle':
        return _buildAppBundle(rest);
      case 'pod':
        return _pod(rest);
      case 'pod-update':
      case 'podupdate':
      case 'pods':
        return _podUpdate(rest);
      case 'signapk':
      case 'sign-apk':
      case 'keystore':
        return _signApk(rest);
      case 'sha':
      case 'sha1':
      case 'sha256':
      case 'keystore-sha':
      case 'signapk-sha':
        return _showKeystoreSha(rest);
      case 'swagger':
      case 'models':
        return _swagger(rest);
      case 'upgrade':
      case 'update':
        return _upgrade(rest);
      case 'help':
        _printHelp();
        return 0;
      default:
        throw CliFailure(
          'Unknown command "$command". Run `fdev --help` to see available commands.',
        );
    }
  } on CliFailure catch (error) {
    stderr.writeln('fdev: ${error.message}');
    return error.exitCode;
  } on FormatException catch (error) {
    stderr.writeln('fdev: ${error.message}');
    return 65;
  } on SocketException catch (error) {
    stderr.writeln('fdev: network error: ${error.message}');
    return 69;
  } on FileSystemException catch (error) {
    stderr.writeln('fdev: file error: ${error.message}');
    return 74;
  }
}

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

Future<int> _pod(List<String> args) async {
  if (args.isEmpty || _isHelp(args.first)) {
    _printPodUpdateHelp();
    return 0;
  }

  if (args.first == 'update') {
    return _podUpdate(args.sublist(1));
  }

  throw const CliFailure('Unsupported pod command. Use `fdev pod update`.');
}

Future<int> _podUpdate(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printPodUpdateHelp();
    return 0;
  }

  _ensurePubspec();

  if (!Platform.isMacOS) {
    throw const CliFailure('iOS Pod update is only supported on macOS.');
  }

  final iosDir = Directory('ios');
  if (!iosDir.existsSync()) {
    throw const CliFailure(
      'No ios directory found. Run this command from your Flutter project root.',
    );
  }

  var exitCode = await _runStep('flutter', const ['clean']);
  if (exitCode != 0) {
    return exitCode;
  }

  exitCode = await _runStep('flutter', const ['pub', 'get']);
  if (exitCode != 0) {
    return exitCode;
  }

  return _runStep(
    'pod',
    ['update', ...args],
    workingDirectory: iosDir.path,
  );
}

Future<int> _signApk(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printSignApkHelp();
    return 0;
  }

  _ensurePubspec();

  final appDir = _androidAppDirectory();
  final parsed = ParsedArgs.parse(
    args,
    optionNames: const {'file', 'alias', 'validity', 'dname'},
    aliases: const {'f': 'file', 'a': 'alias'},
  );

  final fileName = _normalizeNewKeystoreFileName(
    parsed.option('file') ??
        _promptWithDefault('Keystore file name', 'keystore.jks'),
  );
  final alias =
      parsed.option('alias') ?? _promptWithDefault('Key alias', 'upload');
  final validity = _parsePositiveInt(
    parsed.option('validity') ?? '10000',
    optionName: 'validity',
  );
  final storePassword = _promptConfirmedSecret(
    'Store password (min 6 chars): ',
    minLength: 6,
  );
  final keyPasswordInput = _promptSecret(
    'Key password [same as store password]: ',
    allowEmpty: true,
    minLength: 6,
  );
  final keyPassword =
      keyPasswordInput.isEmpty ? storePassword : keyPasswordInput;
  final dname = parsed.option('dname') ??
      _certificateDname(
        _promptWithDefault('Certificate owner name', 'Android Upload Key'),
      );

  final keystoreFile = File('${appDir.path}/$fileName');
  final propertiesFile = File('${appDir.path}/keystore.properties');
  if (keystoreFile.existsSync()) {
    throw CliFailure('${keystoreFile.path} already exists.');
  }
  if (propertiesFile.existsSync()) {
    throw CliFailure('${propertiesFile.path} already exists.');
  }

  stdout.writeln('Step 1/3: Generating ${keystoreFile.path}');
  final generateResult = await _runCaptured('keytool', [
    '-genkeypair',
    '-v',
    '-keystore',
    keystoreFile.path,
    '-storetype',
    'JKS',
    '-keyalg',
    'RSA',
    '-keysize',
    '2048',
    '-validity',
    validity.toString(),
    '-alias',
    alias,
    '-storepass',
    storePassword,
    '-keypass',
    keyPassword,
    '-dname',
    dname,
  ]);
  if (generateResult.exitCode != 0) {
    _printCommandOutput(generateResult);
    return generateResult.exitCode;
  }

  stdout.writeln('Step 2/3: Writing ${propertiesFile.path}');
  await propertiesFile.writeAsString(
    _keystorePropertiesSource(
      storePassword: storePassword,
      keyPassword: keyPassword,
      alias: alias,
      storeFile: fileName,
    ),
  );

  stdout.writeln('Step 3/3: SHA fingerprints');
  final shaExitCode = await _printKeystoreSha(
    keystoreFile: keystoreFile,
    alias: alias,
    storePassword: storePassword,
  );
  if (shaExitCode != 0) {
    return shaExitCode;
  }

  stdout.writeln('');
  stdout.writeln('Created:');
  stdout.writeln('  ${keystoreFile.path}');
  stdout.writeln('  ${propertiesFile.path}');
  stdout.writeln('');
  stdout.writeln('Keep both files private. Do not commit signing passwords.');
  return 0;
}

Future<int> _showKeystoreSha(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printKeystoreShaHelp();
    return 0;
  }

  _ensurePubspec();

  final parsed = ParsedArgs.parse(
    args,
    optionNames: const {'file', 'alias'},
    aliases: const {'f': 'file', 'a': 'alias'},
  );
  final properties = _readExistingKeystoreProperties();
  final defaultFile = properties['storeFile'] ?? _firstAndroidAppJksFileName();
  final fileInput = parsed.option('file') ??
      _promptWithDefault('JKS file name', defaultFile ?? 'keystore.jks');
  final keystoreFile = _resolveExistingKeystoreFile(fileInput);
  if (!keystoreFile.existsSync()) {
    throw CliFailure('${keystoreFile.path} does not exist.');
  }

  final propertyFileName = properties['storeFile'];
  final selectedStoredFile = propertyFileName != null &&
      _fileName(fileInput) == _fileName(propertyFileName);
  final alias = parsed.option('alias') ??
      properties['keyAlias'] ??
      _promptWithDefault('Key alias', 'upload');
  final storePassword = selectedStoredFile
      ? properties['storePassword'] ??
          _promptSecret('Store password: ', minLength: 1)
      : _promptSecret('Store password: ', minLength: 1);

  return _printKeystoreSha(
    keystoreFile: keystoreFile,
    alias: alias,
    storePassword: storePassword,
  );
}

Future<int> _swagger(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printSwaggerHelp();
    return 0;
  }

  final parsed = ParsedArgs.parse(
    args,
    optionNames: const {'url', 'file', 'out', 'root', 'class-prefix'},
    aliases: const {'u': 'url', 'o': 'out'},
  );

  final url = parsed.option('url') ?? await _promptUrlIfNeeded(parsed);
  final inputFile = parsed.option('file');
  if ((url == null || url.isEmpty) &&
      (inputFile == null || inputFile.isEmpty)) {
    throw const CliFailure(
      'Pass `--url <swagger-json-url>` or `--file <swagger.json>`.',
    );
  }

  final outPath = parsed.option('out') ?? 'lib/models/api_models.dart';
  final rootClass = parsed.option('root') ?? 'ApiResponse';
  final classPrefix = parsed.option('class-prefix') ?? '';
  final sourceName = inputFile ?? url!;
  final sourceText = inputFile != null && inputFile.isNotEmpty
      ? await File(inputFile).readAsString()
      : await _downloadText(Uri.parse(url!));

  final generator = SwaggerModelGenerator(
    rootClassName: rootClass,
    classPrefix: classPrefix,
  );
  final result = generator.generate(sourceText, sourceName: sourceName);

  final outFile = File(outPath);
  await outFile.parent.create(recursive: true);
  await outFile.writeAsString(result.source);

  stdout.writeln('Generated ${result.classCount} model classes in $outPath');
  final formatCode = await _runInherited('dart', ['format', outPath]);
  if (formatCode != 0) {
    return formatCode;
  }

  return 0;
}

Future<String?> _promptUrlIfNeeded(ParsedArgs parsed) async {
  if (parsed.option('file') != null) {
    return null;
  }

  stdout.write('Swagger JSON URL: ');
  final value = stdin.readLineSync(encoding: utf8)?.trim();
  return value == null || value.isEmpty ? null : value;
}

String _resolveBuildMode(ParsedArgs parsed, {required String artifact}) {
  if (parsed.hasFlag('debug')) {
    return 'debug';
  }
  if (parsed.hasFlag('profile')) {
    return 'profile';
  }
  if (parsed.hasFlag('release')) {
    return 'release';
  }

  final mode = parsed.option('mode');
  if (mode == null || mode.isEmpty) {
    return 'release';
  }
  if (mode == 'release' || mode == 'debug' || mode == 'profile') {
    return mode;
  }

  throw CliFailure(
    'Unsupported $artifact mode "$mode". Use release, debug, or profile.',
  );
}

void _ensurePubspec() {
  if (!File('pubspec.yaml').existsSync()) {
    throw const CliFailure(
      'No pubspec.yaml found. Run this command from your Flutter project root.',
    );
  }
}

Directory _androidAppDirectory() {
  final directory = Directory('android/app');
  if (!directory.existsSync()) {
    throw const CliFailure(
      'No android/app directory found. Run this from a Flutter project root.',
    );
  }
  return directory;
}

String _normalizeNewKeystoreFileName(String value) {
  final trimmed = value.trim().isEmpty ? 'keystore.jks' : value.trim();
  if (trimmed.contains('/') || trimmed.contains(r'\')) {
    throw const CliFailure(
      'For signapk, pass only a file name. The keystore is saved in android/app.',
    );
  }
  return trimmed.toLowerCase().endsWith('.jks') ? trimmed : '$trimmed.jks';
}

int _parsePositiveInt(String value, {required String optionName}) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw CliFailure('--$optionName must be a positive number.');
  }
  return parsed;
}

String _promptWithDefault(String label, String defaultValue) {
  stdout.write('$label [$defaultValue]: ');
  final value = stdin.readLineSync(encoding: utf8)?.trim();
  return value == null || value.isEmpty ? defaultValue : value;
}

String _promptSecret(
  String label, {
  bool allowEmpty = false,
  int minLength = 0,
}) {
  while (true) {
    stdout.write(label);
    final value = _readHiddenLine();
    if (value.isEmpty && allowEmpty) {
      return value;
    }
    if (value.length >= minLength) {
      return value;
    }
    stderr.writeln('Password must be at least $minLength characters.');
  }
}

String _promptConfirmedSecret(String label, {required int minLength}) {
  while (true) {
    final value = _promptSecret(label, minLength: minLength);
    final confirmation = _promptSecret('Confirm password: ', minLength: 1);
    if (value == confirmation) {
      return value;
    }
    stderr.writeln('Passwords did not match. Try again.');
  }
}

String _readHiddenLine() {
  var echoChanged = false;
  var previousEchoMode = true;
  try {
    if (stdin.hasTerminal) {
      previousEchoMode = stdin.echoMode;
      stdin.echoMode = false;
      echoChanged = true;
    }
  } on StdinException {
    echoChanged = false;
  }

  try {
    return stdin.readLineSync(encoding: utf8) ?? '';
  } finally {
    if (echoChanged) {
      stdin.echoMode = previousEchoMode;
    }
    stdout.writeln();
  }
}

String _certificateDname(String ownerName) {
  final sanitized = ownerName
      .replaceAll(RegExp(r'[,=\r\n]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return 'CN=${sanitized.isEmpty ? 'Android Upload Key' : sanitized}';
}

String _keystorePropertiesSource({
  required String storePassword,
  required String keyPassword,
  required String alias,
  required String storeFile,
}) {
  return '''
storePassword=${_escapePropertiesValue(storePassword)}
keyPassword=${_escapePropertiesValue(keyPassword)}
keyAlias=${_escapePropertiesValue(alias)}
storeFile=${_escapePropertiesValue(storeFile)}
''';
}

String _escapePropertiesValue(String value) {
  var escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t')
      .replaceAll(':', r'\:')
      .replaceAll('=', r'\=')
      .replaceAll('#', r'\#')
      .replaceAll('!', r'\!');
  if (escaped.startsWith(' ')) {
    escaped = '\\$escaped';
  }
  return escaped;
}

Map<String, String> _readExistingKeystoreProperties() {
  for (final file in [
    File('android/app/keystore.properties'),
    File('android/key.properties'),
  ]) {
    if (!file.existsSync()) {
      continue;
    }
    return _readProperties(file);
  }
  return const <String, String>{};
}

Map<String, String> _readProperties(File file) {
  final result = <String, String>{};
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) {
      continue;
    }
    final separatorIndex = _propertiesSeparatorIndex(line);
    if (separatorIndex == -1) {
      continue;
    }
    final key = line.substring(0, separatorIndex).trim();
    final value = line.substring(separatorIndex + 1).trim();
    if (key.isNotEmpty) {
      result[key] = _unescapePropertiesValue(value);
    }
  }
  return result;
}

int _propertiesSeparatorIndex(String line) {
  final equalsIndex = line.indexOf('=');
  final colonIndex = line.indexOf(':');
  if (equalsIndex == -1) {
    return colonIndex;
  }
  if (colonIndex == -1) {
    return equalsIndex;
  }
  return equalsIndex < colonIndex ? equalsIndex : colonIndex;
}

String _unescapePropertiesValue(String value) {
  final buffer = StringBuffer();
  var escaped = false;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (!escaped && char == r'\') {
      escaped = true;
      continue;
    }
    if (escaped) {
      switch (char) {
        case 'n':
          buffer.write('\n');
        case 'r':
          buffer.write('\r');
        case 't':
          buffer.write('\t');
        default:
          buffer.write(char);
      }
      escaped = false;
      continue;
    }
    buffer.write(char);
  }
  if (escaped) {
    buffer.write(r'\');
  }
  return buffer.toString();
}

String? _firstAndroidAppJksFileName() {
  final appDir = Directory('android/app');
  if (!appDir.existsSync()) {
    return null;
  }
  for (final entity in appDir.listSync()) {
    if (entity is File && entity.path.toLowerCase().endsWith('.jks')) {
      return _fileName(entity.path);
    }
  }
  return null;
}

File _resolveExistingKeystoreFile(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return File('android/app/keystore.jks');
  }
  if (_isAbsolutePath(trimmed)) {
    return File(trimmed);
  }
  final hasDirectory = trimmed.contains('/') || trimmed.contains(r'\');
  if (hasDirectory) {
    final direct = File(trimmed);
    if (direct.existsSync()) {
      return direct;
    }
    return File('android/app/$trimmed');
  }
  return File('android/app/$trimmed');
}

String _fileName(String path) {
  return path.split(RegExp(r'[/\\]')).last;
}

bool _isAbsolutePath(String path) {
  return path.startsWith('/') || RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);
}

Future<int> _printKeystoreSha({
  required File keystoreFile,
  required String alias,
  required String storePassword,
}) async {
  final result = await _runCaptured('keytool', [
    '-list',
    '-v',
    '-keystore',
    keystoreFile.path,
    if (alias.isNotEmpty) ...['-alias', alias],
    '-storepass',
    storePassword,
  ]);
  if (result.exitCode != 0) {
    _printCommandOutput(result);
    return result.exitCode;
  }

  final output = result.combinedOutput;
  final sha1 = RegExp(r'SHA1:\s*([0-9A-Fa-f:]+)').firstMatch(output)?.group(1);
  final sha256 =
      RegExp(r'SHA256:\s*([0-9A-Fa-f:]+)').firstMatch(output)?.group(1);

  stdout.writeln('Keystore: ${keystoreFile.path}');
  if (alias.isNotEmpty) {
    stdout.writeln('Alias: $alias');
  }
  stdout.writeln('SHA1: ${sha1 ?? 'not found'}');
  stdout.writeln('SHA256: ${sha256 ?? 'not found'}');
  return 0;
}

Future<String> _downloadText(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json,*/*');
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CliFailure(
        'HTTP ${response.statusCode} while downloading $uri\n$body',
        exitCode: 69,
      );
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

Future<int> _runInherited(String executable, List<String> arguments) async {
  try {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    return process.exitCode;
  } on ProcessException catch (error) {
    throw CliFailure(
      'Could not run `$executable`: ${error.message}',
      exitCode: 127,
    );
  }
}

Future<int> _runStep(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final location = workingDirectory == null ? '' : ' (cwd: $workingDirectory)';
  stdout.writeln('Running: $executable ${arguments.join(' ')}$location');
  try {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    return process.exitCode;
  } on ProcessException catch (error) {
    throw CliFailure(
      'Could not run `$executable`: ${error.message}',
      exitCode: 127,
    );
  }
}

Future<_CommandResult> _runCaptured(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  try {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows,
    );
    final stdoutText = process.stdout.transform(utf8.decoder).join();
    final stderrText = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    return _CommandResult(
      exitCode: exitCode,
      stdoutText: await stdoutText,
      stderrText: await stderrText,
    );
  } on ProcessException catch (error) {
    throw CliFailure(
      'Could not run `$executable`: ${error.message}',
      exitCode: 127,
    );
  }
}

void _printCommandOutput(_CommandResult result) {
  final output = result.combinedOutput.trim();
  if (output.isNotEmpty) {
    stderr.writeln(output);
  }
}

Future<void> _printVersion(String executable, List<String> arguments) async {
  try {
    final result = await Process.run(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );
    final output = [
      if (result.stdout.toString().trim().isNotEmpty)
        result.stdout.toString().trim(),
      if (result.stderr.toString().trim().isNotEmpty)
        result.stderr.toString().trim(),
    ].join('\n');
    stdout.writeln('$executable: ${output.split('\n').first}');
  } on ProcessException catch (error) {
    stdout.writeln('$executable: not available (${error.message})');
  }
}

bool _isHelp(String value) =>
    value == '-h' || value == '--help' || value == 'help';

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
  fdev pod update
  fdev signapk
  fdev sha
  fdev swagger --url https://example.com/swagger.json --out lib/models/api_models.dart
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

Examples:
  fdev swagger --url https://example.com/swagger.json
  fdev swagger --file swagger.json --out lib/data/models/api_models.dart
''');
}

class _CommandResult {
  const _CommandResult({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;

  String get combinedOutput => [
        if (stdoutText.trim().isNotEmpty) stdoutText.trim(),
        if (stderrText.trim().isNotEmpty) stderrText.trim(),
      ].join('\n');
}

const String cliVersion = '0.1.3';

bool _isVersion(String value) =>
    value == '-v' || value == '--version' || value == 'version';

Future<void> _printVersionInfo() async {
  stdout.writeln('fdev version $cliVersion');
  final latest = await _fetchLatestVersion();
  _checkAndPrintUpdate(cliVersion, latest);
}

Future<String?> _fetchLatestVersion() async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 2);
  try {
    final uri = Uri.parse('https://pub.dev/api/packages/fdev');
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode == 200) {
      final body = await utf8.decodeStream(response);
      final data = json.decode(body) as Map<String, dynamic>;
      final latest = data['latest'] as Map<String, dynamic>?;
      if (latest != null) {
        return latest['version'] as String?;
      }
    }
  } catch (_) {
    // Ignore network errors or timeouts to fail silently
  } finally {
    client.close(force: true);
  }
  return null;
}

void _checkAndPrintUpdate(String currentVersion, String? latestVersion) {
  if (latestVersion != null && latestVersion != currentVersion) {
    stdout.writeln();
    stdout.writeln(
        'A new version of fdev is available: $latestVersion (current: $currentVersion).');
    stdout.writeln('Run `fdev upgrade` to update to the latest version.');
  }
}

Future<int> _upgrade(List<String> args) async {
  stdout.writeln('Upgrading fdev to the latest version...');

  final exitCode =
      await _runStep('dart', ['pub', 'global', 'activate', 'fdev']);
  if (exitCode == 0) {
    stdout.writeln('Successfully upgraded fdev!');
  } else {
    stdout.writeln('Failed to upgrade fdev.');
  }
  return exitCode;
}

class ParsedArgs {
  const ParsedArgs({
    required this.flags,
    required this.options,
    required this.positionals,
    required this.passthrough,
  });

  final Set<String> flags;
  final Map<String, List<String>> options;
  final List<String> positionals;
  final List<String> passthrough;

  static ParsedArgs parse(
    List<String> args, {
    required Set<String> optionNames,
    required Map<String, String> aliases,
    Set<String> repeatableOptions = const {},
  }) {
    final flags = <String>{};
    final options = <String, List<String>>{};
    final positionals = <String>[];
    final passthrough = <String>[];

    var index = 0;
    while (index < args.length) {
      final raw = args[index];
      if (raw == '--') {
        passthrough.addAll(args.sublist(index + 1));
        break;
      }

      if (raw.startsWith('--')) {
        final withoutPrefix = raw.substring(2);
        final splitIndex = withoutPrefix.indexOf('=');
        final name = splitIndex == -1
            ? withoutPrefix
            : withoutPrefix.substring(0, splitIndex);
        final canonical = aliases[name] ?? name;
        final inlineValue =
            splitIndex == -1 ? null : withoutPrefix.substring(splitIndex + 1);

        if (optionNames.contains(canonical)) {
          final value =
              inlineValue ?? _consumeOptionValue(args, index, canonical);
          _addOption(options, canonical, value, repeatableOptions);
          index += inlineValue == null ? 2 : 1;
          continue;
        }

        flags.add(canonical);
        index++;
        continue;
      }

      if (raw.startsWith('-') && raw.length > 1) {
        final shortName = raw.substring(1);
        final canonical = aliases[shortName] ?? shortName;
        if (optionNames.contains(canonical)) {
          final value = _consumeOptionValue(args, index, canonical);
          _addOption(options, canonical, value, repeatableOptions);
          index += 2;
          continue;
        }
        flags.add(canonical);
        index++;
        continue;
      }

      positionals.add(raw);
      index++;
    }

    return ParsedArgs(
      flags: flags,
      options: options,
      positionals: positionals,
      passthrough: passthrough,
    );
  }

  bool hasFlag(String name) => flags.contains(name);

  String? option(String name) => options[name]?.last;

  static String _consumeOptionValue(List<String> args, int index, String name) {
    if (index + 1 >= args.length || args[index + 1] == '--') {
      throw CliFailure('Missing value for --$name.');
    }
    return args[index + 1];
  }

  static void _addOption(
    Map<String, List<String>> options,
    String name,
    String value,
    Set<String> repeatableOptions,
  ) {
    if (!repeatableOptions.contains(name) && options.containsKey(name)) {
      options[name] = [value];
      return;
    }
    options.putIfAbsent(name, () => <String>[]).add(value);
  }
}
