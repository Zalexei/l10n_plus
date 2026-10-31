@TestOn('vm')
library;

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:test/test.dart';

import 'support/interchange_fixture.dart';

void main() {
  group('csv', () {
    test('one row per message, one column per locale, base locale first', () {
      final project = makeProject(
        translations: {
          'en.json': '{"a": "A", "b": "B"}',
          'ru.json': '{"a": "А"}',
          'de.json': '{"a": "A", "b": "B"}',
        },
        configYaml: interchangeConfigYaml,
      );

      final result = TranslationExporter.export(
        catalog: project.catalog,
        format: InterchangeFormat.csv,
      );
      final rows = Csv.decode(
        result.files.single.contents,
      ).map((record) => record.map((field) => field.value).toList()).toList();

      // The base locale leads, because that is the column a translator reads
      // first; the rest are in a stable order rather than the file system's.
      expect(rows.first, ['key', 'description', 'en', 'de', 'ru']);
      expect(rows[1], ['a', '', 'A', 'A', 'А']);
      // An untranslated message leaves the cell empty, which is what a
      // translator looks for.
      expect(rows[2], ['b', '', 'B', 'B', '']);
      expect(result.messageCount, 2);
    });

    test('the description column carries what the source declared', () {
      final project = copyFixture('arb');
      final rows = Csv.decode(
        TranslationExporter.export(
          catalog: project.catalog,
          format: InterchangeFormat.csv,
        ).files.single.contents,
      ).map((record) => record.map((field) => field.value).toList()).toList();

      final title = rows.firstWhere((row) => row.first == 'auth.login.title');
      expect(title[1], 'Title of the login screen');
      // A format with nowhere to put one leaves it empty rather than absent:
      // the header stays the same whatever the project's formats are, so a
      // spreadsheet never has to be told which columns to expect.
      final tip = rows.firstWhere((row) => row.first == 'wallet.tip');
      expect(tip[1], '');
    });

    test('counts what is untranslated per locale', () {
      final project = makeProject(
        translations: {
          'en.json': '{"a": "A", "b": "B", "c": "C"}',
          'ru.json': '{"a": "А"}',
        },
        configYaml: interchangeConfigYaml,
      );
      final result = TranslationExporter.export(
        catalog: project.catalog,
        format: InterchangeFormat.csv,
      );
      expect(
        {
          for (final locale in result.coverage)
            locale.localeTag: locale.untranslated,
        },
        {'en': 0, 'ru': 2},
      );
    });

    test('a key only another locale has is not exported', () {
      // The base locale is the generated API. A key it does not define cannot
      // be called from anywhere, so sending it to a translator would be
      // buying work that cannot be used.
      final project = makeProject(
        translations: {
          'en.json': '{"a": "A"}',
          'ru.json': '{"a": "А", "z": "Я"}',
        },
        configYaml: interchangeConfigYaml,
      );
      final rows = Csv.decode(
        TranslationExporter.export(
          catalog: project.catalog,
          format: InterchangeFormat.csv,
        ).files.single.contents,
      );
      expect(rows.skip(1).map((row) => row.first.value), ['a']);
    });
  });

  group('arb', () {
    test('one bundle per locale, each naming its own locale', () {
      final project = copyFixture('json');
      final result = TranslationExporter.export(
        catalog: project.catalog,
        format: InterchangeFormat.arb,
      );
      expect(result.files.map((file) => file.name), ['en.arb', 'ru.arb']);
      for (final file in result.files) {
        expect(
          file.contents,
          contains('"@@locale": "${file.name.split('.').first}"'),
        );
      }
    });

    test('a target bundle carries the base text as source_text', () {
      final project = copyFixture('json');
      final result = TranslationExporter.export(
        catalog: project.catalog,
        format: InterchangeFormat.arb,
      );
      final ru = result.files.firstWhere((file) => file.name == 'ru.arb');
      expect(ru.contents, contains('"source_text": "Balance: {amount}"'));

      // Not in the base locale's own bundle: there it would be the message
      // repeated back at itself.
      final en = result.files.firstWhere((file) => file.name == 'en.arb');
      expect(en.contents, isNot(contains('source_text')));
    });

    test('an untranslated message is left out, never filled from the base', () {
      // The failure this prevents: a bundle that answers "translated" for
      // every key, and English shipping as Russian.
      final project = makeProject(
        translations: {
          'en.json': '{"a": "A", "b": "B"}',
          'ru.json': '{"a": "А"}',
        },
        configYaml: interchangeConfigYaml,
      );
      final ru = TranslationExporter.export(
        catalog: project.catalog,
        format: InterchangeFormat.arb,
      ).files.firstWhere((file) => file.name == 'ru.arb');

      expect(ru.contents, contains('"a": "А"'));
      expect(ru.contents, isNot(contains('"b"')));
    });

    test('metadata only ever sits next to its message', () {
      // `@key` without `key` is an error in this generator's own ARB reader,
      // so a bundle carrying one is a bundle we could not read back.
      final project = makeProject(
        translations: {
          'en.json': '{"a": "A", "b": "B"}',
          'ru.json': '{"a": "А"}',
        },
        configYaml: interchangeConfigYaml,
      );
      final ru = TranslationExporter.export(
        catalog: project.catalog,
        format: InterchangeFormat.arb,
      ).files.firstWhere((file) => file.name == 'ru.arb');

      final diagnostics = DiagnosticCollector();
      InterchangeBundle.readArb(
        files: [(uri: Uri.parse('memory:/ru.arb'), content: ru.contents)],
        diagnostics: diagnostics,
      );
      expect(diagnostics.diagnostics, isEmpty);
    });

    test('placeholders travel, so a TMS knows what not to translate', () {
      final project = copyFixture('arb');
      final ru = TranslationExporter.export(
        catalog: project.catalog,
        format: InterchangeFormat.arb,
      ).files.firstWhere((file) => file.name == 'ru.arb');

      expect(ru.contents, contains('"placeholders"'));
      expect(ru.contents, contains('"example": "Alex"'));
      // Presentation is not carried: it is declared per locale and `import`
      // never writes metadata back, so claiming it would be a round trip the
      // import does not make.
      expect(ru.contents, isNot(contains('optionalParameters')));
    });
  });

  group('the CLI', () {
    test(
      'export exits zero and writes where --out says',
      () {
        final project = copyFixture('json');
        final result = runCli(project.root, [
          'export',
          '--out=hand_off/strings.csv',
        ]);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect('${result.stdout}', contains('hand_off/strings.csv'));
        expect(
          project.translations.keys,
          containsAll(['translations/en.json', 'translations/ru.json']),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'export refuses a file where it needs a directory',
      () {
        final project = copyFixture('json');
        project.write('taken.txt', 'not a directory');
        final result = runCli(project.root, [
          'export',
          '--format=arb',
          '--out=taken.txt',
        ]);
        expect(result.exitCode, 64);
        expect('${result.stderr}', contains('one bundle per locale'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'an unknown format is refused before anything is read',
      () {
        final project = copyFixture('json');
        final result = runCli(project.root, ['export', '--format=xliff']);
        expect(result.exitCode, 64);
        expect('${result.stderr}', contains('Unknown format "xliff"'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      '--out is refused for the commands it cannot mean anything for',
      () {
        final project = copyFixture('json');
        final result = runCli(project.root, ['generate', '--out=somewhere']);
        expect(result.exitCode, 64);
        expect('${result.stderr}', contains('only available for "export"'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'an incomplete locale is exportable, which is the whole point',
      () {
        // `fill_missing_from_base` is off here, so `analyze` calls the missing
        // key an error. Export must not: that locale is the reason someone is
        // exporting.
        final project = makeProject(
          translations: {
            'en.json': '{"a": "A", "b": "B"}',
            'ru.json': '{"a": "А"}',
          },
          configYaml: interchangeConfigYaml,
        );
        expect(runCli(project.root, ['analyze']).exitCode, isNot(0));

        final result = runCli(project.root, ['export']);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect('${result.stdout}', contains('ru  1 of 2'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a file that cannot be parsed stops the export',
      () {
        final project = makeProject(
          translations: {'en.json': '{"a": "A"', 'ru.json': '{"a": "А"}'},
          configYaml: interchangeConfigYaml,
        );
        final result = runCli(project.root, ['export']);
        expect(result.exitCode, 1);
        expect('${result.stdout}${result.stderr}', contains('invalid_json'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      '--help describes both commands',
      () {
        final project = copyFixture('json');
        final result = runCli(project.root, ['export', '--help']);
        final text = '${result.stdout}';
        expect(text, contains('export'));
        expect(text, contains('import'));
        expect(text, contains('--write'));
        expect(text, contains('--from'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
