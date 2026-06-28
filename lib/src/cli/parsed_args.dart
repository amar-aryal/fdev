part of '../cli.dart';

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
