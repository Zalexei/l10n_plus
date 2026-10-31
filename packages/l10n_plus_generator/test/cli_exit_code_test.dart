@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The CLI, run as a process.
///
/// The exit code is the whole contract with CI, and it is decided in `bin/`,
/// which no in-process test reaches.
void main() {
  // Not `Directory.current`: the suite is run from the workspace root too.
  final packageRoot = p.dirname(
    p.dirname(
      Isolate.resolvePackageUriSync(
        Uri.parse('package:l10n_plus_generator/l10n_plus_generator.dart'),
      )!.toFilePath(),
    ),
  );

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('l10n_plus_cli');
    Directory(p.join(root.path, 'translations')).createSync(recursive: true);
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: probe\n');
  });

  tearDown(() => root.deleteSync(recursive: true));

  void write(String relative, String contents) =>
      File(p.join(root.path, relative)).writeAsStringSync(contents);

  ProcessResult run(String command) =>
      Process.runSync(Platform.resolvedExecutable, [
        'run',
        p.join(packageRoot, 'bin/l10n_plus_generator.dart'),
        command,
        '--no-highlight',
      ], workingDirectory: root.path);

  const goodConfig = '''
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

  test('a clean project exits zero and writes', () {
    write('l10n_plus.yaml', goodConfig);
    write('translations/en.json', '{"a": "A"}');
    final result = run('generate');
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(
      File(p.join(root.path, 'lib/l10n/app_localizations.g.dart')).existsSync(),
      isTrue,
    );
  });

  test('a translation error exits non zero', () {
    write('l10n_plus.yaml', goodConfig);
    write('translations/en.json', '{"a": "Hello {name"}');
    expect(run('generate').exitCode, isNot(0));
    expect(run('analyze').exitCode, isNot(0));
  });

  group('a configuration error', () {
    // `L10nPlusConfig.parse` reports the bad value and carries on with the
    // default, so a caller that only inspects the generation result would
    // generate from a configuration it had already called wrong.
    void writeBadConfig() {
      write('l10n_plus.yaml', '$goodConfig\nformat_plural_numbers: "maybe"\n');
      write('translations/en.json', '{"a": "A"}');
    }

    test('exits non zero from generate', () {
      writeBadConfig();
      final result = run('generate');
      expect(result.exitCode, isNot(0));
      expect('${result.stdout}${result.stderr}', contains('invalid_config'));
    });

    test('exits non zero from analyze, which is the CI command', () {
      writeBadConfig();
      final result = run('analyze');
      expect(result.exitCode, isNot(0));
      expect('${result.stdout}${result.stderr}', isNot(contains('No errors.')));
    });

    test('writes nothing', () {
      writeBadConfig();
      run('generate');
      expect(Directory(p.join(root.path, 'lib')).existsSync(), isFalse);
    });

    test('reports the error once, not once per collector', () {
      writeBadConfig();
      final result = run('generate');
      final output = '${result.stdout}${result.stderr}';
      expect('invalid_config'.allMatches(output).length, 1);
    });
  });

  test('an unknown key is a warning and still generates', () {
    write('l10n_plus.yaml', '$goodConfig\nfile_per_local: true\n');
    write('translations/en.json', '{"a": "A"}');
    final result = run('generate');
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect('${result.stdout}', contains('unknown_config_key'));
  });

  group('the analyze summary', () {
    const fillConfig = '''
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
fill_missing_from_base: true
flutter:
  enabled: false
''';

    test('reports how much of each locale is translated', () {
      write('l10n_plus.yaml', fillConfig);
      write('translations/en.json', '{"a": "A", "b": "B", "c": "C", "d": "D"}');
      write('translations/ru.json', '{"a": "А"}');
      write('translations/de.json', '{"a": "A", "b": "B", "c": "C", "d": "D"}');

      final result = run('analyze');
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      final output = '${result.stdout}';
      expect(output, contains('Translated:'));
      expect(output, contains('ru  1/4  (25%, 3 untranslated)'));
      expect(output, contains('de  4/4'));
      expect(output, contains('en  4/4'));
    });

    test('says nothing when every locale is complete', () {
      // A table of 100%s on every run is noise; silence is the report.
      write('l10n_plus.yaml', fillConfig);
      write('translations/en.json', '{"a": "A"}');
      write('translations/ru.json', '{"a": "А"}');

      final result = run('analyze');
      expect(result.exitCode, 0);
      expect('${result.stdout}', isNot(contains('Translated:')));
    });

    test('a single locale project says nothing either', () {
      write('l10n_plus.yaml', fillConfig);
      write('translations/en.json', '{"a": "A"}');

      expect('${run('analyze').stdout}', isNot(contains('Translated:')));
    });
  });

  group('--watch', () {
    const goodConfigLocal = '''
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

    test('is refused for the commands that answer once', () {
      write('l10n_plus.yaml', goodConfigLocal);
      write('translations/en.json', '{"a": "A"}');
      for (final command in ['analyze', 'unused']) {
        final result = Process.runSync(Platform.resolvedExecutable, [
          'run',
          p.join(packageRoot, 'bin/l10n_plus_generator.dart'),
          command,
          '--watch',
          '--no-highlight',
        ], workingDirectory: root.path);
        expect(result.exitCode, 64, reason: command);
        expect('${result.stderr}', contains('only available for "generate"'));
      }
    });

    test('refuses to watch a translation directory that is not there', () {
      write('l10n_plus.yaml', goodConfigLocal);
      // No translations/ at all: the first run reports it, and there is
      // nothing to watch afterwards.
      Directory(p.join(root.path, 'translations')).deleteSync();
      final result = Process.runSync(Platform.resolvedExecutable, [
        'run',
        p.join(packageRoot, 'bin/l10n_plus_generator.dart'),
        'generate',
        '--watch',
        '--no-highlight',
      ], workingDirectory: root.path);
      expect(result.exitCode, isNot(0));
      expect('${result.stdout}${result.stderr}', contains('translations'));
    });

    test(
      'regenerates when a translation changes, and keeps running',
      () async {
        write('l10n_plus.yaml', goodConfigLocal);
        write('translations/en.json', '{"greeting": "Hello"}');

        final process = await Process.start(Platform.resolvedExecutable, [
          'run',
          p.join(packageRoot, 'bin/l10n_plus_generator.dart'),
          'generate',
          '--watch',
          '--no-highlight',
        ], workingDirectory: root.path);
        addTearDown(() => process.kill(ProcessSignal.sigkill));

        final output = StringBuffer();
        process.stdout.transform(utf8.decoder).listen(output.write);
        process.stderr.transform(utf8.decoder).listen(output.write);

        /// Polls rather than sleeps: a fixed wait is either flaky on a loaded
        /// machine or slow on every other one.
        Future<void> waitFor(String text, {required String reason}) async {
          final deadline = DateTime.now().add(const Duration(seconds: 40));
          while (DateTime.now().isBefore(deadline)) {
            if (output.toString().contains(text)) return;
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          fail('$reason\nWaited for "$text" in:\n$output');
        }

        await waitFor('Watching', reason: 'the watcher never started');
        final generated = File(
          p.join(root.path, 'lib/l10n/app_localizations.g.dart'),
        );
        expect(generated.readAsStringSync(), contains("'Hello'"));

        /// Waits for the watcher to say it wrote, and for the file to hold
        /// [text]. Watching only the log would race the write itself.
        Future<void> expectRebuiltTo(String text, {required int after}) async {
          final deadline = DateTime.now().add(const Duration(seconds: 40));
          while (DateTime.now().isBefore(deadline)) {
            if ('wrote'.allMatches(output.toString()).length > after &&
                generated.readAsStringSync().contains("'$text'")) {
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          fail('Never regenerated with "$text". Output:\n$output');
        }

        var writes = 'wrote'.allMatches(output.toString()).length;
        write('translations/en.json', '{"greeting": "Hei"}');
        await expectRebuiltTo('Hei', after: writes);

        // A second edit, to prove the watcher is still listening rather than
        // having fired once and stopped.
        writes = 'wrote'.allMatches(output.toString()).length;
        write('translations/en.json', '{"greeting": "Moi"}');
        await expectRebuiltTo('Moi', after: writes);

        expect(process.kill(), isTrue, reason: 'it should still be running');
        // `dart run` compiles the CLI before it starts watching, so the
        // default 30 second budget is spent before the first rebuild.
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
