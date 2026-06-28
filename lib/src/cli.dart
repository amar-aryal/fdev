import 'dart:convert';
import 'dart:io';

import 'swagger_generator.dart';

part 'cli/project_commands.dart';
part 'cli/pod_commands.dart';
part 'cli/signing_commands.dart';
part 'cli/swagger_command.dart';
part 'cli/helpers.dart';
part 'cli/help.dart';
part 'cli/process.dart';
part 'cli/version.dart';
part 'cli/parsed_args.dart';

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
        return await _doctor(rest);
      case 'gen':
      case 'runner':
      case 'build-runner':
        return await _buildRunner(rest);
      case 'clean':
        return await _clean(rest);
      case 'apk':
      case 'build-apk':
        return await _buildApk(rest);
      case 'appbundle':
      case 'aab':
      case 'build-appbundle':
        return await _buildAppBundle(rest);
      case 'ios':
      case 'build-ios':
        return await _buildIos(rest);
      case 'icons':
      case 'launcher-icons':
        return await _launcherIcons(rest);
      case 'splash':
      case 'native-splash':
        return await _nativeSplash(rest);
      case 'env':
        return await _env(rest);
      case 'release-notes':
      case 'changelog':
        return await _releaseNotes(rest);
      case 'pod':
        return await _pod(rest);
      case 'pod-update':
      case 'podupdate':
      case 'pods':
        return await _podUpdate(rest);
      case 'signapk':
      case 'sign-apk':
      case 'keystore':
        return await _signApk(rest);
      case 'sha':
      case 'sha1':
      case 'sha256':
      case 'keystore-sha':
      case 'signapk-sha':
        return await _showKeystoreSha(rest);
      case 'swagger':
      case 'models':
        return await _swagger(rest);
      case 'upgrade':
      case 'update':
        return await _upgrade(rest);
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
