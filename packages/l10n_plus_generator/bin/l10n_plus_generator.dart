import 'dart:io';

import 'package:args/args.dart';
import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;

/// Exit code returned when translations contain errors.
const int _exitCodeDiagnostics = 1;

/// Exit code returned when the command line itself was wrong.
const int _exitCodeUsage = 64;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help: 'Path to the configuration file.',
      defaultsTo: L10nPlusConfig.defaultFileName,
    )
    ..addFlag(
      'no-highlight',
      negatable: false,
      help: 'Print diagnostics without source snippets.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this usage.');

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage(parser));
    exit(_exitCodeUsage);
  }

  final command = results.rest.isEmpty ? null : results.rest.first;
  if (results.flag('help') || command == null) {
    stdout.writeln(_usage(parser));
    exit(command == null ? _exitCodeUsage : 0);
  }
  const commands = {'generate', 'analyze', 'unused'};
  if (!commands.contains(command)) {
    stderr.writeln('Unknown command "$command".');
    stderr.writeln(_usage(parser));
    exit(_exitCodeUsage);
  }

  final configPath = results.option('config')!;
  final configFile = File(configPath);
  if (!configFile.existsSync()) {
    stderr.writeln('Configuration file "$configPath" not found.');
    stderr.writeln(
      'Create it, or point at another file with --config. A minimal file:\n'
      '\n'
      '  input_directory: translations\n'
      '  output_directory: lib/generated\n'
      '  base_locale: en\n',
    );
    exit(_exitCodeDiagnostics);
  }

  final diagnostics = DiagnosticCollector();
  final config = L10nPlusConfig.parse(
    configFile.readAsStringSync(),
    uri: configFile.uri,
    diagnostics: diagnostics,
  );
  final highlight = !results.flag('no-highlight');
  if (config == null) {
    _report(diagnostics.diagnostics, highlight: highlight);
    exit(_exitCodeDiagnostics);
  }

  final generator = L10nPlusGenerator(
    config: config,
    projectRoot: p.dirname(p.absolute(configPath)),
  );
  final result = generator.run(diagnostics: diagnostics);
  // `run` was given the configuration's collector, so its diagnostics are
  // already in the result; a second list would print each one twice.
  final all = result.diagnostics;
  _report(all, highlight: highlight);

  if (result.hasErrors) {
    stderr.writeln(_summary(all, ignored: result.ignoredCount));
    exit(_exitCodeDiagnostics);
  }

  if (command == 'unused') {
    final unused = generator.findUnusedKeys(result);
    _report(unused.diagnostics, highlight: highlight);
    if (unused.isEmpty) {
      stdout.writeln('No unused keys. ${result.keys.length} checked.');
      exit(0);
    }
    stderr.writeln(
      '${unused.keyCount} of ${result.keys.length} key(s) appear unused, '
      'in ${unused.diagnostics.length} place(s).',
    );
    exit(_exitCodeDiagnostics);
  }

  if (command == 'analyze') {
    stdout.writeln(
      'No errors. ${_summary(all, ignored: result.ignoredCount)}'.trim(),
    );
    exit(0);
  }

  final written = generator.write(result.files);
  for (final file in result.files) {
    final changed = written.contains(file.path);
    stdout.writeln('${changed ? 'wrote' : 'unchanged'} ${file.path}');
  }
  exit(0);
}

void _report(List<Diagnostic> diagnostics, {required bool highlight}) {
  for (final diagnostic in diagnostics) {
    final sink = diagnostic.severity == Severity.error ? stderr : stdout;
    sink
      ..writeln(diagnostic.format(highlight: highlight))
      ..writeln();
  }
}

String _summary(List<Diagnostic> diagnostics, {int ignored = 0}) {
  final errors = diagnostics.where((d) => d.severity == Severity.error).length;
  final warnings = diagnostics
      .where((d) => d.severity == Severity.warning)
      .length;
  if (errors == 0 && warnings == 0 && ignored == 0) return '';
  // The ignored count is always shown: a warning silenced by a config nobody
  // remembers writing is worse than the warning was.
  final suppressed = ignored == 0 ? '' : ' $ignored ignored.';
  return '$errors error(s), $warnings warning(s).$suppressed';
}

String _usage(ArgParser parser) => '''
Type safe localization code generation.

Usage: dart run l10n_plus_generator <command> [options]

Commands:
  generate   Validate translations and write the generated Dart files.
  analyze    Validate translations only. Exits non-zero on any error.
  unused     Report translations no Dart source refers to. Names are matched
             as text, so a key is reported only when its member name appears
             nowhere at all. Exits non-zero when any are found.

Options:
${parser.usage}''';
