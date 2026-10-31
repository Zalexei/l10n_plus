import 'dart:async';
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
    ..addFlag(
      'watch',
      abbr: 'w',
      negatable: false,
      help: 'Regenerate whenever a translation or the configuration changes.',
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
  final highlight = !results.flag('no-highlight');
  final watch = results.flag('watch');
  if (watch && command != 'generate') {
    stderr.writeln('--watch is only available for "generate".');
    stderr.writeln(
      '"$command" answers a question once; watching would only repeat the '
      'answer. Run it again when you want it again.',
    );
    exit(_exitCodeUsage);
  }

  final outcome = _runCommand(
    command: command,
    configPath: configPath,
    highlight: highlight,
  );
  if (!watch) exit(outcome.exitCode);

  final config = outcome.config;
  if (config == null) exit(outcome.exitCode);
  await _watch(configPath: configPath, config: config, highlight: highlight);
}

/// What one run produced: its exit code, and the configuration it read.
///
/// The configuration comes back because watching needs to know which
/// directory to watch, and it is the run that discovers that.
final class _RunOutcome {
  const _RunOutcome(this.exitCode, [this.config]);

  final int exitCode;
  final L10nPlusConfig? config;
}

/// Runs [command] once, printing everything it has to say.
///
/// Returns rather than exits: the same run happens on every file change in
/// watch mode, where exiting would be the last thing anyone wants.
_RunOutcome _runCommand({
  required String command,
  required String configPath,
  required bool highlight,
}) {
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
    return const _RunOutcome(_exitCodeDiagnostics);
  }

  final diagnostics = DiagnosticCollector();
  final config = L10nPlusConfig.parse(
    configFile.readAsStringSync(),
    uri: configFile.uri,
    diagnostics: diagnostics,
  );
  if (config == null) {
    _report(diagnostics.diagnostics, highlight: highlight);
    return const _RunOutcome(_exitCodeDiagnostics);
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
    return _RunOutcome(_exitCodeDiagnostics, config);
  }

  if (command == 'unused') {
    final unused = generator.findUnusedKeys(result);
    _report(unused.diagnostics, highlight: highlight);
    if (unused.isEmpty) {
      stdout.writeln('No unused keys. ${result.keys.length} checked.');
      return _RunOutcome(0, config);
    }
    stderr.writeln(
      '${unused.keyCount} of ${result.keys.length} key(s) appear unused, '
      'in ${unused.diagnostics.length} place(s).',
    );
    return _RunOutcome(_exitCodeDiagnostics, config);
  }

  if (command == 'analyze') {
    stdout.writeln(
      'No errors. ${_summary(all, ignored: result.ignoredCount)}'.trim(),
    );
    _reportCoverage(result.coverage);
    return _RunOutcome(0, config);
  }

  final written = generator.write(result.files);
  for (final file in result.files) {
    final changed = written.contains(file.path);
    stdout.writeln('${changed ? 'wrote' : 'unchanged'} ${file.path}');
  }
  return _RunOutcome(0, config);
}

/// Regenerates on every change until interrupted.
///
/// Watches the translation directory and the project root — the first for the
/// files themselves, the second for `l10n_plus.yaml` and `pubspec.yaml`, both
/// of which change what generation produces. The output directory is never
/// watched: it is what this writes.
///
/// The configuration is re-read on every run, so editing it takes effect
/// without restarting.
Future<void> _watch({
  required String configPath,
  required L10nPlusConfig config,
  required bool highlight,
}) async {
  final configAbsolute = p.absolute(configPath);
  final root = p.dirname(configAbsolute);
  final input = Directory(p.join(root, config.inputDirectory));
  if (!input.existsSync()) {
    stderr.writeln(
      'Cannot watch "${config.inputDirectory}": the directory does not '
      'exist. Create it and start again.',
    );
    exit(_exitCodeDiagnostics);
  }

  stdout.writeln('');
  stdout.writeln(
    'Watching ${config.inputDirectory}/ and ${p.basename(configPath)}. '
    'Ctrl-C to stop.',
  );

  // Editors save in bursts — a temporary file, a rename, a truncate — and a
  // save-and-format is two bursts. Waiting for quiet turns each of those into
  // one run instead of four.
  const quiet = Duration(milliseconds: 120);
  Timer? pending;
  var running = false;
  var again = false;

  void rebuild() {
    if (running) {
      // A change arrived mid-run; the run may have read a stale file.
      again = true;
      return;
    }
    running = true;
    stdout.writeln('');
    stdout.writeln('--- ${DateTime.now().toIso8601String()} ---');
    try {
      _runCommand(
        command: 'generate',
        configPath: configPath,
        highlight: highlight,
      );
    } finally {
      running = false;
    }
    if (again) {
      again = false;
      rebuild();
    }
  }

  void onEvent(FileSystemEvent event) {
    // Compared against the paths handed to `watch`, and never canonicalized:
    // `p.canonicalize` does not resolve symbolic links, so a project reached
    // through one — a temporary directory on macOS, for instance — would
    // compare `/var/…` against `/private/var/…` and match nothing.
    final path = event.path;
    final isTranslation = p.isWithin(input.path, path);
    final isProjectFile =
        p.equals(path, configAbsolute) ||
        p.basename(path) == 'pubspec.yaml' && p.equals(p.dirname(path), root);
    if (!isTranslation && !isProjectFile) return;
    pending?.cancel();
    pending = Timer(quiet, rebuild);
  }

  final subscriptions = [
    input.watch(recursive: true).listen(onEvent),
    // Not recursive: the root holds the two files that matter, and going
    // deeper would watch the generated output and rebuild on its own writes.
    Directory(root).watch().listen(onEvent),
  ];

  // Nothing completes this; the process runs until it is interrupted.
  await Future.wait(subscriptions.map((s) => s.asFuture<void>()));
}

/// Per locale translation coverage, when there is anything to say.
///
/// "0 error(s), 18 warning(s)" does not answer "how far along is French",
/// which is the only question a partially translated project is asking. The
/// warnings each name a subtree; this counts messages.
void _reportCoverage(List<LocaleCoverage> coverage) {
  if (coverage.every((locale) => locale.isComplete)) return;
  final width = coverage
      .map((locale) => locale.locale.length)
      .fold(0, (a, b) => a > b ? a : b);
  stdout.writeln('');
  stdout.writeln('Translated:');
  for (final locale in coverage) {
    stdout.writeln(
      '  ${locale.locale.padRight(width)}  '
      '${locale.translated}/${locale.total}'
      '${locale.isComplete ? '' : '  '
                '(${locale.percent}%, ${locale.untranslated} untranslated)'}',
    );
  }
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
