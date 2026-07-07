part of '../cli.dart';

const String cliVersion = '0.1.5';

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
