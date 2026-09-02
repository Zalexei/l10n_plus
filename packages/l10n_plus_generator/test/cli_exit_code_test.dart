@TestOn('vm')
library;

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
}
