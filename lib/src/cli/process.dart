part of '../cli.dart';

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
