part of '../cli.dart';

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
