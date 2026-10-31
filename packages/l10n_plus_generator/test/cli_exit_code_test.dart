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

  group('check-overrides', () {
    const overrideConfig = """
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
runtime_overrides: true
flutter:
  enabled: false
""";

    ProcessResult check(List<String> extra) =>
        Process.runSync(Platform.resolvedExecutable, [
          'run',
          p.join(packageRoot, 'bin/l10n_plus_generator.dart'),
          'check-overrides',
          '--no-highlight',
          ...extra,
        ], workingDirectory: root.path);

    void writeProject() {
      write('l10n_plus.yaml', overrideConfig);
      write(
        'translations/en.json',
        '{"title": "Log in", '
            '"items": "{n, plural, one{# item} other{# items}}"}',
      );
    }

    test('a bundle with everything right but a fingerprint is refused', () {
      // The last thing a correct bundle is missing: a statement of which
      // build it is correct for. Refusing it is what makes the statement
      // something every shipped bundle has.
      writeProject();
      write('overrides_en.json', '{"@@locale": "en", "title": "Sign in"}');
      final result = check(['--from=overrides_en.json']);
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('missing_override_fingerprint'));
      expect('${result.stderr}', contains('--stamp'));
    });

    test('--stamp signs the bundle it checked, and the check then passes', () {
      writeProject();
      write('overrides_en.json', '{"@@locale": "en", "title": "Sign in"}');

      final stamped = check(['--from=overrides_en.json', '--stamp']);
      expect(stamped.exitCode, 0, reason: '${stamped.stdout}${stamped.stderr}');
      expect('${stamped.stdout}', contains('stamped'));

      // Written in place, as the first entry, leaving the file's own text
      // alone.
      final content = File(
        p.join(root.path, 'overrides_en.json'),
      ).readAsStringSync();
      expect(content, contains('"@@fingerprint": "'));
      expect(content, contains('"@@locale": "en"'));
      expect(content, contains('"title": "Sign in"'));

      final again = check(['--from=overrides_en.json']);
      expect(again.exitCode, 0, reason: '${again.stdout}${again.stderr}');
      expect('${again.stdout}', contains('No errors.'));
      // It validates; it is not a build step.
      expect(Directory(p.join(root.path, 'lib')).existsSync(), isFalse);

      // Idempotent: the same build signs the same bundle the same way.
      final third = check(['--from=overrides_en.json', '--stamp']);
      expect(third.exitCode, 0);
      expect('${third.stdout}', contains('unchanged'));
    });

    test('a bundle signed for another build is refused', () {
      writeProject();
      write(
        'overrides_en.json',
        '{"@@fingerprint": "0123456789abcdef", '
            '"@@locale": "en", "title": "Sign in"}',
      );
      final result = check(['--from=overrides_en.json']);
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('override_fingerprint_mismatch'));
      expect('${result.stderr}', contains('0123456789abcdef'));
    });

    test('a bundle that is wrong exits one, which is the CI contract', () {
      writeProject();
      write('overrides_en.json', '{"@@locale": "en", "ttitle": "Sign in"}');
      final result = check(['--from=overrides_en.json']);
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('unknown_override_key'));
    });

    test('no --from is a usage error, with the example', () {
      writeProject();
      final result = check([]);
      expect(result.exitCode, 64);
      expect('${result.stderr}', contains('needs --from'));
      expect('${result.stderr}', contains('overrides_en.json'));
    });

    test('an option that cannot mean anything here is refused', () {
      writeProject();
      write('overrides_en.json', '{"@@locale": "en", "title": "Sign in"}');
      final result = check(['--from=overrides_en.json', '--write']);
      expect(result.exitCode, 64);
      expect('${result.stderr}', contains('--write'));
    });

    test('a project with the option off is told to turn it on', () {
      // Checking a bundle against a project that consults nothing would pass
      // and then do nothing, which is the worst of the available answers.
      write('l10n_plus.yaml', goodConfig);
      write('translations/en.json', '{"title": "Log in"}');
      write('overrides_en.json', '{"@@locale": "en", "title": "Sign in"}');
      final result = check(['--from=overrides_en.json']);
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('runtime_overrides: true'));
    });

    test('a project that does not build is reported instead of guessed at', () {
      // The slots are what the emitter wrote, so there are none to check
      // against until the project generates.
      write('l10n_plus.yaml', overrideConfig);
      write('translations/en.json', '{"title": "Hello {name"}');
      write('overrides_en.json', '{"@@locale": "en", "title": "Sign in"}');
      final result = check(['--from=overrides_en.json']);
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('icu_unclosed_argument'));
    });

    test('a file that is not there, and a directory that is', () {
      writeProject();
      expect(check(['--from=nothing.json']).exitCode, 1);
      Directory(p.join(root.path, 'bundles')).createSync();
      final result = check(['--from=bundles']);
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('one locale'));
    });

    test(
      '--watch is refused, as it is for every command that answers once',
      () {
        writeProject();
        write('overrides_en.json', '{"@@locale": "en", "title": "Sign in"}');
        final result = check(['--from=overrides_en.json', '--watch']);
        expect(result.exitCode, 64);
      },
    );
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
