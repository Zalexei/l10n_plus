import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:l10n_plus/l10n_plus.dart';
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
    ..addOption(
      'format',
      help:
          'Interchange format for "export" and "import" '
          '(${InterchangeFormat.names}). Defaults to csv for "export", and '
          'for "import" to what --from looks like.',
      valueHelp: 'name',
    )
    ..addOption(
      'out',
      help:
          'Where "export" writes: a file for csv, a directory for arb. '
          'Defaults to ./${TranslationExporter.defaultCsvFileName} and '
          './$_defaultExportDirectory/.',
      valueHelp: 'dir|file',
    )
    ..addOption(
      'from',
      help:
          'What "import" reads: the csv file, or the arb bundle or directory '
          'of bundles, that came back from the translators. What '
          '"check-overrides" reads: the json override bundle.',
      valueHelp: 'dir|file',
    )
    ..addFlag(
      'write',
      negatable: false,
      help:
          'Let "import" change the translation files. Without it the import '
          'prints what it would change and writes nothing.',
    )
    ..addFlag(
      'stamp',
      negatable: false,
      help:
          'Let "check-overrides" write this build\'s fingerprint into the '
          'bundle it just checked. Without it a bundle that states none is an '
          'error, because nothing would stop it being installed into another '
          'build.',
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
  const commands = {
    'generate',
    'analyze',
    'unused',
    'export',
    'import',
    'check-overrides',
  };
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

  // An option that cannot mean anything for this command is refused rather
  // than ignored: a translator who runs `import --out=…` and sees nothing
  // happen has every reason to believe the files were written.
  for (final misplaced in [
    ('format', results.option('format') != null, {'export', 'import'}),
    ('out', results.option('out') != null, {'export'}),
    ('from', results.option('from') != null, {'import', 'check-overrides'}),
    ('write', results.flag('write'), {'import'}),
    ('stamp', results.flag('stamp'), {'check-overrides'}),
  ]) {
    if (!misplaced.$2 || misplaced.$3.contains(command)) continue;
    stderr.writeln(
      '--${misplaced.$1} is only available for '
      '${misplaced.$3.map((name) => '"$name"').join(' and ')}.',
    );
    exit(_exitCodeUsage);
  }

  final formatName = results.option('format');
  if (formatName != null && InterchangeFormat.byName(formatName) == null) {
    stderr.writeln('Unknown format "$formatName".');
    stderr.writeln('The formats are ${InterchangeFormat.names}.');
    exit(_exitCodeUsage);
  }

  final from = results.option('from');
  if (command == 'import' && from == null) {
    stderr.writeln('"import" needs --from: the file the translators sent.');
    stderr.writeln(
      'For example:\n'
      '  dart run l10n_plus_generator import '
      '--from=${TranslationExporter.defaultCsvFileName}',
    );
    exit(_exitCodeUsage);
  }
  if (command == 'check-overrides' && from == null) {
    stderr.writeln(
      '"check-overrides" needs --from: the override bundle to check.',
    );
    stderr.writeln(
      'For example:\n'
      '  dart run l10n_plus_generator check-overrides '
      '--from=overrides_en.json',
    );
    exit(_exitCodeUsage);
  }

  final outcome = _runCommand(
    command: command,
    configPath: configPath,
    highlight: highlight,
    format: formatName == null ? null : InterchangeFormat.byName(formatName),
    out: results.option('out'),
    from: from,
    write: results.flag('write'),
    stamp: results.flag('stamp'),
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
  InterchangeFormat? format,
  String? out,
  String? from,
  bool write = false,
  bool stamp = false,
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

  final projectRoot = p.dirname(p.absolute(configPath));

  // The interchange commands run before validation rather than after it, and
  // the order is the whole point. Under the default configuration a locale
  // missing keys is an error — and that locale is the reason someone is
  // exporting. A round trip that only ran on a project with nothing left to
  // translate would be a workflow for nobody, so these two read the files,
  // report what the parsers say, and leave cross locale validation to
  // `analyze`.
  if (command == 'export' || command == 'import') {
    final exitCode = command == 'export'
        ? _export(
            config: config,
            projectRoot: projectRoot,
            format: format ?? InterchangeFormat.csv,
            out: out,
            highlight: highlight,
            diagnostics: diagnostics,
          )
        : _import(
            config: config,
            projectRoot: projectRoot,
            format: format,
            from: from!,
            write: write,
            highlight: highlight,
            diagnostics: diagnostics,
          );
    return _RunOutcome(exitCode, config);
  }

  final generator = L10nPlusGenerator(config: config, projectRoot: projectRoot);
  final result = generator.run(diagnostics: diagnostics);
  // `run` was given the configuration's collector, so its diagnostics are
  // already in the result; a second list would print each one twice.
  final all = result.diagnostics;
  _report(all, highlight: highlight);

  if (result.hasErrors) {
    stderr.writeln(_summary(all, ignored: result.ignoredCount));
    return _RunOutcome(_exitCodeDiagnostics, config);
  }

  if (command == 'check-overrides') {
    return _RunOutcome(
      _checkOverrides(
        result: result,
        from: from!,
        highlight: highlight,
        stamp: stamp,
      ),
      config,
    );
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

/// Validates a runtime override bundle against what the project emitted.
///
/// Runs after generation rather than instead of it, and the order is the
/// point: the slots a bundle is checked against are the lookups the emitter
/// wrote, so a project that does not build has no slots to check against and
/// an answer here would be a guess. The two interchange commands run *before*
/// validation for the opposite reason — an incomplete locale is why somebody
/// exports, and it is never why somebody ships an override.
int _checkOverrides({
  required GenerationResult result,
  required String from,
  required bool highlight,
  required bool stamp,
}) {
  if (result.overrides.isEmpty) {
    _report([
      const Diagnostic.error(
        code: 'invalid_override',
        message: 'This project does not consult overrides at run time.',
        details:
            'Turn them on in l10n_plus.yaml:\n'
            '  runtime_overrides: true\n'
            'With it off the generated code returns its literals and nothing '
            'reads a bundle, so checking one would pass and mean nothing.',
      ),
    ], highlight: highlight);
    return _exitCodeDiagnostics;
  }

  if (Directory(from).existsSync()) {
    _report([
      Diagnostic.error(
        code: 'invalid_override',
        message: '"$from" is a directory, and a bundle is one locale.',
        details:
            'Name the .json file. Run the command once per locale: each '
            'bundle is checked against that locale\'s own plural '
            'categories, which is most of what this command is for.',
      ),
    ], highlight: highlight);
    return _exitCodeDiagnostics;
  }
  final file = File(from);
  if (!file.existsSync()) {
    _report([
      Diagnostic.error(
        code: 'invalid_override',
        message: 'Nothing to check: "$from" does not exist.',
      ),
    ], highlight: highlight);
    return _exitCodeDiagnostics;
  }

  final diagnostics = DiagnosticCollector();
  final content = file.readAsStringSync();
  final bundle = OverrideBundle.read(
    content: content,
    uri: file.uri,
    path: file.path,
    diagnostics: diagnostics,
  );
  if (bundle != null) {
    OverrideChecker.check(
      bundle: bundle,
      catalog: result.overrides,
      diagnostics: diagnostics,
      // With --stamp the fingerprint is an output rather than an input, so
      // the two diagnostics about it would be complaints about the work this
      // run is here to do. Everything else is still checked, and nothing is
      // written if any of it fails: a stamp says this bundle was validated.
      requireFingerprint: !stamp,
    );
  }
  _report(diagnostics.diagnostics, highlight: highlight);

  if (diagnostics.hasErrors) {
    stderr.writeln(_summary(diagnostics.diagnostics));
    stderr.writeln(
      'An override is text; the shape around it is the one the application '
      'compiled.',
    );
    return _exitCodeDiagnostics;
  }

  final texts = bundle!.messages.fold<int>(
    0,
    (total, message) => total + message.texts.length,
  );
  final schema = result.overrides.forLocale(bundle.localeTag)!;
  final fingerprint = OverrideFingerprint.of(schema);
  if (stamp) {
    final stamped = _stamp(
      content: content,
      bundle: bundle,
      fingerprint: fingerprint,
    );
    if (stamped == null) {
      stdout.writeln('unchanged ${file.path}');
    } else {
      file.writeAsStringSync(stamped);
      stdout.writeln('stamped ${file.path}');
    }
  }
  stdout.writeln(
    '${bundle.messages.length} of ${schema.messages.length} message(s) '
    'overridden in "${bundle.localeTag}", $texts text(s). No errors.',
  );
  stdout.writeln('Overridable surface of "${bundle.localeTag}": $fingerprint');
  return 0;
}

/// Writes [fingerprint] into [content], or returns `null` when it is there.
///
/// An edit rather than a re-serialization, for the reason `import` edits
/// instead of rewriting: the file belongs to whoever wrote it, and reformatting
/// it to this tool's taste would turn one changed character into a diff nobody
/// can review.
String? _stamp({
  required String content,
  required OverrideBundle bundle,
  required String fingerprint,
}) {
  if (bundle.fingerprint == fingerprint) return null;
  final stated = bundle.fingerprintSpan;
  if (stated != null) {
    return content.replaceRange(
      stated.start.offset,
      stated.end.offset,
      '"$fingerprint"',
    );
  }
  final root = bundle.rootSpan;
  if (root == null) return null;
  // First, so it is the first thing read in a file that is read by people as
  // often as by programs, and laid out the way the file already lays its own
  // members out: beside the next one when that one shares the brace's line,
  // and on a line of its own at its indentation otherwise.
  final first = bundle.firstMemberSpan;
  final entry = '"${L10nOverrides.fingerprintKey}": "$fingerprint"';
  final at = root.start.offset + 1;
  final String insertion;
  if (first == null) {
    insertion = entry;
  } else if (first.start.line == root.start.line) {
    insertion = '$entry, ';
  } else {
    insertion = '\n${' ' * first.start.column}$entry,';
  }
  return content.replaceRange(at, at, insertion);
}

/// Directory `export --format=arb` writes into when `--out` says nothing.
const String _defaultExportDirectory = 'l10n_plus_export';

/// Writes every message out for whoever translates it.
///
/// A file nothing can read stops this. A locale that is merely incomplete is
/// the reason to run it, so nothing here asks whether the project validates.
int _export({
  required L10nPlusConfig config,
  required String projectRoot,
  required InterchangeFormat format,
  required String? out,
  required bool highlight,
  required DiagnosticCollector diagnostics,
}) {
  diagnostics.ignore(config.ignoreDiagnostics);
  final catalog = TranslationCatalog.load(
    config: config,
    projectRoot: projectRoot,
    diagnostics: diagnostics,
  );
  _report(diagnostics.diagnostics, highlight: highlight);
  if (catalog == null || diagnostics.hasErrors) return _exitCodeDiagnostics;

  final result = TranslationExporter.export(catalog: catalog, format: format);

  // csv is one file and arb is one per locale, so `--out` means a file in the
  // first case and a directory in the second. A path that is plainly the other
  // kind is refused rather than reinterpreted.
  final String directory;
  String? fileName;
  if (format == InterchangeFormat.csv) {
    final target = out ?? TranslationExporter.defaultCsvFileName;
    final isDirectory =
        Directory(target).existsSync() ||
        target.endsWith(p.separator) ||
        target.endsWith('/');
    directory = isDirectory ? target : (p.dirname(target));
    fileName = isDirectory ? null : p.basename(target);
  } else {
    final target = out ?? _defaultExportDirectory;
    if (File(target).existsSync()) {
      stderr.writeln(
        '"--out=$target" is a file, and "--format=arb" writes one bundle per '
        'locale.',
      );
      stderr.writeln('Name a directory instead.');
      return _exitCodeUsage;
    }
    directory = target;
  }

  Directory(directory).createSync(recursive: true);
  for (final file in result.files) {
    // Normalized, so that a default `--out` prints `export.csv` rather than
    // `./export.csv`; the path in the report is one someone may paste back.
    final path = p.normalize(p.join(directory, fileName ?? file.name));
    File(path).writeAsStringSync(file.contents);
    stdout.writeln('wrote $path');
  }

  stdout.writeln(
    '${result.messageCount} message(s), '
    '${result.coverage.length} locale(s).',
  );

  final behind = result.coverage
      .where((locale) => locale.untranslated > 0)
      .toList(growable: false);
  if (behind.isEmpty) {
    stdout.writeln('Every locale is complete.');
    return 0;
  }
  final width = behind
      .map((locale) => locale.localeTag.length)
      .fold(0, (a, b) => a > b ? a : b);
  stdout.writeln('');
  stdout.writeln('Untranslated:');
  for (final locale in behind) {
    stdout.writeln(
      '  ${locale.localeTag.padRight(width)}  '
      '${locale.untranslated} of ${locale.total}',
    );
  }
  return 0;
}

/// Puts what the translators sent back into the project's own files.
///
/// Writes nothing unless asked to. The plan is computed in full either way, so
/// the dry run is the same work as the real thing minus the last step rather
/// than a separate estimate of it.
int _import({
  required L10nPlusConfig config,
  required String projectRoot,
  required InterchangeFormat? format,
  required String from,
  required bool write,
  required bool highlight,
  required DiagnosticCollector diagnostics,
}) {
  diagnostics.ignore(config.ignoreDiagnostics);

  // Every stage adds to one collector, and only what is new since the last
  // stage is printed: reporting the whole list twice is how a report starts
  // saying everything twice.
  var reported = 0;
  void flush() {
    _report(
      diagnostics.diagnostics.skip(reported).toList(growable: false),
      highlight: highlight,
    );
    reported = diagnostics.diagnostics.length;
  }

  final isDirectory = Directory(from).existsSync();
  if (!isDirectory && !File(from).existsSync()) {
    _report([
      Diagnostic.error(
        code: 'invalid_interchange',
        message: 'Nothing to import: "$from" does not exist.',
        details: 'Point --from at the file or directory "export" produced.',
      ),
    ], highlight: highlight);
    return _exitCodeDiagnostics;
  }

  // A directory can only be ARB bundles, and a `.arb` file says so itself;
  // anything else is read as CSV, which is what a spreadsheet produces.
  final resolved =
      format ??
      (isDirectory || p.extension(from).toLowerCase() == '.arb'
          ? InterchangeFormat.arb
          : InterchangeFormat.csv);

  final catalog = TranslationCatalog.load(
    config: config,
    projectRoot: projectRoot,
    diagnostics: diagnostics,
  );
  flush();
  if (catalog == null || diagnostics.hasErrors) return _exitCodeDiagnostics;

  final InterchangeBundle? bundle;
  if (resolved == InterchangeFormat.csv) {
    if (isDirectory) {
      _report([
        Diagnostic.error(
          code: 'invalid_interchange',
          message: '"$from" is a directory, and csv is one file.',
          details:
              'Name the .csv file, or pass --format=arb for a directory of '
              'bundles.',
        ),
      ], highlight: highlight);
      return _exitCodeDiagnostics;
    }
    final file = File(from);
    bundle = InterchangeBundle.readCsv(
      content: file.readAsStringSync(),
      uri: file.uri,
      diagnostics: diagnostics,
    );
  } else {
    final files = <({Uri uri, String content})>[];
    if (isDirectory) {
      final found =
          Directory(from)
              .listSync()
              .whereType<File>()
              .where((file) => p.extension(file.path).toLowerCase() == '.arb')
              .toList(growable: false)
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in found) {
        files.add((uri: file.uri, content: file.readAsStringSync()));
      }
      if (files.isEmpty) {
        _report([
          Diagnostic.error(
            code: 'invalid_interchange',
            message: 'No .arb file in "$from".',
          ),
        ], highlight: highlight);
        return _exitCodeDiagnostics;
      }
    } else {
      final file = File(from);
      files.add((uri: file.uri, content: file.readAsStringSync()));
    }
    bundle = InterchangeBundle.readArb(files: files, diagnostics: diagnostics);
  }

  flush();
  if (bundle == null || diagnostics.hasErrors) return _exitCodeDiagnostics;

  final result = TranslationImporter.plan(
    catalog: catalog,
    bundle: bundle,
    diagnostics: diagnostics,
  );
  flush();
  if (result.hasErrors) return _exitCodeDiagnostics;

  for (final locale in result.locales) {
    if (locale.messages.isEmpty && locale.unchanged == 0) continue;
    stdout.writeln(
      '${locale.localeTag}: ${locale.added} added, ${locale.changed} changed, '
      '${locale.unchanged} unchanged.',
    );
    for (final message in locale.messages) {
      switch (message.change) {
        case ImportChange.added:
          stdout.writeln('  + ${message.key}  (${message.file})');
          stdout.writeln('      ${message.after}');
        case ImportChange.changed:
          stdout.writeln('  ~ ${message.key}  (${message.file})');
          stdout.writeln('      - ${message.before}');
          stdout.writeln('      + ${message.after}');
      }
    }
    stdout.writeln('');
  }

  if (result.isEmpty) {
    stdout.writeln('Nothing to import: every message already matches.');
    return 0;
  }

  if (!write) {
    stdout.writeln(
      'Dry run: ${result.writes.length} file(s) would change, and nothing '
      'was written.',
    );
    for (final pending in result.writes) {
      stdout.writeln('  would write ${pending.relativePath}');
    }
    stdout.writeln('Pass --write to apply it.');
    return 0;
  }

  for (final pending in result.writes) {
    File(pending.path).writeAsStringSync(pending.contents);
    stdout.writeln('wrote ${pending.relativePath}');
  }
  stdout.writeln(
    'Run "analyze" next: an import can write ICU the base locale disagrees '
    'with, and that is a build error rather than a bad string.',
  );
  return 0;
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
  export     Write every message out for a translator: the base locale's text,
             each locale's current translation, and what is missing.
  import     Read what "export" wrote and update the translation files, in the
             project's own formats and file layout. Prints what it would
             change and writes nothing until --write.
  check-overrides
             Validate a runtime override bundle against this project. Needs
             runtime_overrides: true, and exits non-zero on any problem.

Translator workflow:
  dart run l10n_plus_generator export                     one csv, all locales
  dart run l10n_plus_generator export --format=arb        one arb per locale
  dart run l10n_plus_generator export --out=hand_off.csv

  dart run l10n_plus_generator import --from=hand_off.csv          dry run
  dart run l10n_plus_generator import --from=hand_off.csv --write  apply
  dart run l10n_plus_generator import --from=from_tms/ --write

  A csv cell holds the message exactly as the file does, ICU and all, and an
  empty cell means "not translated" rather than "translate it to nothing". An
  arb export leaves an untranslated message out of the bundle, and carries the
  base text along as "source_text".

  "import" only ever changes a message's text. It adds keys a locale does not
  have yet, never deletes one, never touches a key the base locale does not
  define, and never rewrites a file beyond the characters that changed — so
  your key order, comments and indentation survive.

Runtime overrides:
  dart run l10n_plus_generator check-overrides --from=overrides_en.json
  dart run l10n_plus_generator check-overrides --from=overrides_en.json --stamp

  A bundle is JSON, flat, keyed by the dotted translation key: a string for a
  message with one form, and one string per branch for a plural or a select.
  The locale comes from "@@locale", or from the file name.

    {
      "@@locale": "en",
      "auth.login.title": "Sign in",
      "wallet.transactions": {"=0": "Nothing yet", "one": "# payment",
                              "other": "# payments"}
    }

  An override is text and only text: {name} takes the value the generated code
  has already formatted, # the plural count, and {#0} the rendering of the
  message's first nested choice. Writing ICU in it is an error, because the
  plural rules and the number formats are compiled into the application and
  nothing at run time would read them.

  The check answers, with the project in hand: whether the key exists, whether
  the branch is one this locale can produce -- "few" is real in Russian and a
  mistake in English -- whether the placeholders are ones the message takes,
  and whether a rich message is being asked to be text.

  Those answers are about the project as it stands, and a bundle outlives a
  build: branches of a nested choice are addressed by position, so a message
  that gains a choice renumbers the ones after it while every name in an old
  bundle still exists. So a checked bundle carries the surface it was checked
  against, which --stamp writes:

    {"@@fingerprint": "6c1dd0a2f8e34b19", "@@locale": "en", ...}

  The generated AppLocale.en.installOverrides(bundle) passes this build's own
  and refuses any other, leaving the application on the text it compiled.

Options:
${parser.usage}''';
