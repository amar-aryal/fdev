part of '../cli.dart';

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
