part of '../cli.dart';

Future<int> _swagger(List<String> args) async {
  if (args.isNotEmpty && _isHelp(args.first)) {
    _printSwaggerHelp();
    return 0;
  }

  final parsed = ParsedArgs.parse(
    args,
    optionNames: const {
      'url',
      'file',
      'out',
      'root',
      'class-prefix',
      'interval',
    },
    aliases: const {'u': 'url', 'o': 'out'},
  );

  final watch = parsed.hasFlag('watch');
  final inputFile = parsed.option('file');
  if (watch) {
    if (inputFile == null || inputFile.isEmpty) {
      throw const CliFailure(
        '`--watch` requires a local `--file <swagger.json>` to monitor.',
      );
    }
    return _swaggerWatch(parsed);
  }

  return _swaggerRun(parsed);
}

Future<int> _swaggerRun(ParsedArgs parsed) async {
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

Future<int> _swaggerWatch(ParsedArgs parsed) async {
  final inputFile = parsed.option('file')!;
  final outPath = parsed.option('out') ?? 'lib/models/api_models.dart';
  final pollSeconds = _parsePositiveInt(
    parsed.option('interval') ?? '2',
    optionName: 'interval',
  );

  stdout.writeln('Watching ${inputFile} -> ${outPath} '
      '(poll every ${pollSeconds}s). Press Ctrl+C to stop.');

  var lastModified = await File(inputFile).stat();
  var firstRun = await _swaggerRegenerate(parsed, reason: 'initial');
  if (firstRun != 0) {
    return firstRun;
  }

  while (true) {
    await Future<void>.delayed(Duration(seconds: pollSeconds));
    final current = await File(inputFile).stat();
    if (current.modified.isAfter(lastModified.modified)) {
      lastModified = current;
      final code = await _swaggerRegenerate(parsed, reason: 'change detected');
      if (code != 0) {
        stdout
            .writeln('Regeneration failed (exit $code). Continuing to watch.');
      }
    }
  }
}

Future<int> _swaggerRegenerate(ParsedArgs parsed,
    {required String reason}) async {
  stdout.writeln('\n[swagger --watch] $reason');
  return _swaggerRun(parsed);
}

Future<String?> _promptUrlIfNeeded(ParsedArgs parsed) async {
  if (parsed.option('file') != null) {
    return null;
  }

  stdout.write('Swagger JSON URL: ');
  final value = stdin.readLineSync(encoding: utf8)?.trim();
  return value == null || value.isEmpty ? null : value;
}
