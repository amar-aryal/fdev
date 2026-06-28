part of '../cli.dart';

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
