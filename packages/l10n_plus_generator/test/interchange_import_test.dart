@TestOn('vm')
library;

import 'dart:io';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/interchange_fixture.dart';

/// Plans the import of [csv] into [project], and applies it when asked.
///
/// Mirrors what the CLI does, so a test can make the same claims about the
/// files on disk that a user would see.
({ImportResult result, List<Diagnostic> diagnostics}) importCsv(
  Project project,
  String csv, {
  bool write = false,
}) {
  final diagnostics = DiagnosticCollector();
  final bundle = InterchangeBundle.readCsv(
    content: csv,
    uri: Uri.parse('memory:/hand_off.csv'),
    diagnostics: diagnostics,
  );
  if (bundle == null) {
    return (
      result: const ImportResult(diagnostics: [], locales: [], writes: []),
      diagnostics: diagnostics.diagnostics,
    );
  }
  final result = TranslationImporter.plan(
    catalog: project.catalog,
    bundle: bundle,
    diagnostics: diagnostics,
  );
  if (write) {
    for (final pending in result.writes) {
      File(pending.path).writeAsStringSync(pending.contents);
    }
  }
  return (result: result, diagnostics: diagnostics.diagnostics);
}

void main() {
  group('what it reports', () {
    test('added, changed and unchanged, per locale', () {
      final project = makeProject(
        translations: {
          'en.json': '{"a": "A", "b": "B", "c": "C"}',
          'ru.json': '{"a": "А", "b": "Б"}',
        },
        configYaml: interchangeConfigYaml,
      );

      final outcome = importCsv(project, '''
key,description,en,ru
a,,A,А
b,,B,Бэ
c,,C,Це
''');

      final ru = outcome.result.locales.firstWhere((l) => l.localeTag == 'ru');
      expect(ru.added, 1);
      expect(ru.changed, 1);
      expect(ru.unchanged, 1);
      expect(
        ru.messages.map((m) => '${m.change.name} ${m.key}'),
        containsAll(['changed b', 'added c']),
      );

      final en = outcome.result.locales.firstWhere((l) => l.localeTag == 'en');
      expect(en.unchanged, 3);
      expect(en.messages, isEmpty);
    });

    test('a key the base locale does not define is refused once', () {
      // Once, not once per locale: one key deleted from the base locale would
      // otherwise fill the report with a line per language.
      final project = makeProject(
        translations: {'en.json': '{"a": "A"}', 'ru.json': '{"a": "А"}'},
        configYaml: interchangeConfigYaml,
      );
      final outcome = importCsv(project, '''
key,description,en,ru
a,,A,А
gone,,Gone,Ушло
''');

      final reported = outcome.diagnostics
          .where((d) => d.code == 'unknown_interchange_key')
          .toList();
      expect(reported, hasLength(1));
      expect(reported.single.severity, Severity.warning);
      expect(reported.single.translationKey, 'gone');
      expect(reported.single.span, isNotNull, reason: 'it must name the row');
      expect(outcome.result.writes, isEmpty);
    });

    test('a locale the project has no files for is refused, with the fix', () {
      final project = makeProject(
        translations: {'en.json': '{"a": "A"}'},
        configYaml: interchangeConfigYaml,
      );
      final outcome = importCsv(project, '''
key,description,en,fr
a,,A,Aaa
''');

      final reported = outcome.diagnostics.singleWhere(
        (d) => d.code == 'unknown_interchange_locale',
      );
      expect(reported.message, contains('fr'));
      expect(reported.details, contains('Add one translation file'));
      expect(outcome.result.writes, isEmpty);
    });

    test('a column that is not a locale is ignored, not guessed at', () {
      final project = makeProject(
        translations: {'en.json': '{"a": "A"}', 'ru.json': '{"a": "А"}'},
        configYaml: interchangeConfigYaml,
      );
      final outcome = importCsv(project, '''
key,description,en,ru,Comments
a,,A,А,ask the client
''');

      expect(
        outcome.diagnostics.map((d) => d.code),
        contains('unknown_interchange_column'),
      );
      expect(outcome.result.writes, isEmpty);
    });

    test('an empty cell means nothing was supplied, not an empty message', () {
      final project = makeProject(
        translations: {
          'en.json': '{"a": "A", "b": "B"}',
          'ru.json': '{"a": "А"}',
        },
        configYaml: interchangeConfigYaml,
      );
      final outcome = importCsv(project, '''
key,description,en,ru
a,,A,А
b,,B,
''');
      expect(outcome.result.writes, isEmpty);
      expect(outcome.diagnostics, isEmpty);
    });
  });

  group('what it writes', () {
    test('a changed message, and nothing around it', () {
      final project = copyFixture('yaml');
      final before = project.translations;
      final outcome = importCsv(project, '''
key,description,en,ru
wallet.balance,,Balance: {amount},"Остаток: {amount}"
''', write: true);

      expect(outcome.result.writes, hasLength(1));
      final after = project.translations;
      expect(after['translations/en.yaml'], before['translations/en.yaml']);
      expect(
        after['translations/ru.yaml'],
        before['translations/ru.yaml']!.replaceFirst(
          "'Баланс: {amount}'",
          "'Остаток: {amount}'",
        ),
      );
    });

    test('a new key joins its siblings at their own indentation', () {
      final project = makeProject(
        translations: {
          'en.json': '{\n  "wallet": {\n    "a": "A",\n    "b": "B"\n  }\n}\n',
          'ru.json': '{\n  "wallet": {\n    "a": "А"\n  }\n}\n',
        },
        configYaml: interchangeConfigYaml,
      );
      importCsv(project, '''
key,description,en,ru
wallet.a,,A,А
wallet.b,,B,Бэ
''', write: true);

      expect(
        project.translations['translations/ru.json'],
        '{\n  "wallet": {\n    "a": "А",\n    "b": "Бэ"\n  }\n}\n',
      );
    });

    test('a new group is created once, however many keys go in it', () {
      // Two additions under one new group must produce one group. Two would
      // be a duplicate key, so the import would have broken the build it was
      // meant to fix.
      final project = makeProject(
        translations: {
          'en.json':
              '{\n  "a": "A",\n  "limits": {\n    "x": "X",\n    "y": "Y"\n  }\n}\n',
          'ru.json': '{\n  "a": "А"\n}\n',
        },
        configYaml: interchangeConfigYaml,
      );
      importCsv(project, '''
key,description,en,ru
a,,A,А
limits.x,,X,Икс
limits.y,,Y,Игрек
''', write: true);

      expect(
        project.translations['translations/ru.json'],
        '{\n  "a": "А",\n  "limits": {\n    "x": "Икс",\n    "y": "Игрек"\n  }\n}\n',
      );
      // And it still reads as what was asked for.
      final catalog = project.catalog;
      expect(catalog.localeFor('ru')!.messages['limits.y']!.raw, 'Игрек');
    });

    test('YAML gets a YAML scalar, JSON a JSON string', () {
      // The same message through the same import, encoded twice: each the way
      // the file it lands in already writes a string, with that format's own
      // way of doubling a quote.
      const message = "Бэ, и ещё 'кавычки'";
      final csv = Csv.encode([
        ['key', 'description', 'en', 'ru'],
        ['wallet.a', '', 'A', 'А'],
        ['wallet.b', '', 'B', message],
      ]);

      final yaml = makeProject(
        translations: {
          'en.yaml': "wallet:\n  a: 'A'\n  b: 'B'\n",
          'ru.yaml': "wallet:\n  a: 'А'\n",
        },
        configYaml: interchangeConfigYaml,
      );
      importCsv(yaml, csv, write: true);
      expect(
        yaml.translations['translations/ru.yaml'],
        "wallet:\n  a: 'А'\n  b: 'Бэ, и ещё ''кавычки'''\n",
      );

      final json = makeProject(
        translations: {
          'en.json': '{\n  "wallet": {\n    "a": "A",\n    "b": "B"\n  }\n}\n',
          'ru.json': '{\n  "wallet": {\n    "a": "А"\n  }\n}\n',
        },
        configYaml: interchangeConfigYaml,
      );
      importCsv(json, csv, write: true);
      expect(
        json.translations['translations/ru.json'],
        '{\n  "wallet": {\n    "a": "А",\n'
        '    "b": "Бэ, и ещё \'кавычки\'"\n  }\n}\n',
      );

      // And both read back as the one message that was sent.
      for (final project in [yaml, json]) {
        expect(
          project.catalog.localeFor('ru')!.messages['wallet.b']!.raw,
          message,
        );
      }
    });

    test('a message with a newline is written so that it reads back', () {
      // Single quoted YAML cannot hold a line break without folding deciding
      // what it means, so those fall back to double quotes.
      final project = makeProject(
        translations: {'en.yaml': "a: 'A'\nb: 'B'\n", 'ru.yaml': "a: 'А'\n"},
        configYaml: interchangeConfigYaml,
      );
      importCsv(
        project,
        Csv.encode([
          ['key', 'description', 'en', 'ru'],
          ['a', '', 'A', 'first\nsecond'],
          ['b', '', 'B', 'tab\there'],
        ]),
        write: true,
      );

      final catalog = project.catalog;
      expect(catalog.localeFor('ru')!.messages['a']!.raw, 'first\nsecond');
      expect(catalog.localeFor('ru')!.messages['b']!.raw, 'tab\there');
    });

    test('a CRLF file gets CRLF, not a line of its own kind', () {
      // A repository checked out on Windows has CRLF translation files, and
      // one LF line turns the next diff into a file with mixed endings that
      // nobody changed on purpose.
      final project = makeProject(
        translations: {
          'en.json':
              '{\r\n  "wallet": {\r\n    "a": "A",\r\n'
              '    "limits": {\r\n      "b": "B"\r\n    }\r\n  }\r\n}\r\n',
          'ru.json': '{\r\n  "wallet": {\r\n    "a": "А"\r\n  }\r\n}\r\n',
        },
        configYaml: interchangeConfigYaml,
      );
      importCsv(
        project,
        Csv.encode([
          ['key', 'description', 'en', 'ru'],
          ['wallet.limits.b', '', 'B', 'Бэ'],
        ]),
        write: true,
      );

      final written = project.translations['translations/ru.json']!;
      expect(written, isNot(contains(RegExp('[^\r]\n'))));
      expect(
        written,
        '{\r\n  "wallet": {\r\n    "a": "А",\r\n'
        '    "limits": {\r\n      "b": "Бэ"\r\n    }\r\n  }\r\n}\r\n',
      );
    });

    test('a key never deleted, even when the file does not mention it', () {
      final project = copyFixture('json');
      final before = project.translations;
      importCsv(project, '''
key,description,en,ru
auth.login.title,,Log in,Войти
''', write: true);
      expect(project.translations, before);
    });
  });

  group('the project\'s own file layout', () {
    test('a new key goes in the file whose namespace claims it', () {
      // `split` is `{locale}/{namespace}`: three files per locale, two
      // formats. A new `wallet.*` key belongs in `wallet.arb` and nowhere
      // else, and the ARB file is flat so the key is written in full.
      final project = copyFixture('split');
      project.write(
        'translations/en/wallet.arb',
        project.translations['translations/en/wallet.arb']!.replaceFirst(
          '"cards":',
          '"fee": "Fee: {amount}",\n  "cards":',
        ),
      );

      final outcome = importCsv(
        project,
        Csv.encode([
          ['key', 'description', 'en', 'ru'],
          ['wallet.fee', '', 'Fee: {amount}', 'Сбор: {amount}'],
        ]),
        write: true,
      );

      expect(
        outcome.result.writes.single.relativePath,
        p.join('translations', 'ru', 'wallet.arb'),
      );
      // Written in full, because an ARB file nests with dots rather than
      // containers — and the namespace the path already named is taken off.
      expect(
        project.translations['translations/ru/wallet.arb'],
        contains('"fee": "Сбор: {amount}"'),
      );
      expect(
        project.catalog.localeFor('ru')!.messages['wallet.fee'],
        isNotNull,
      );
    });

    test('an untouched file of the same locale stays untouched', () {
      final project = copyFixture('split');
      final before = project.translations;
      importCsv(
        project,
        Csv.encode([
          ['key', 'description', 'en', 'ru'],
          ['auth.login.title', '', 'Log in', 'Вход'],
        ]),
        write: true,
      );

      final after = project.translations;
      expect(
        after['translations/ru/wallet.arb'],
        before['translations/ru/wallet.arb'],
      );
      expect(
        after['translations/ru/profile.json'],
        before['translations/ru/profile.json'],
      );
      expect(
        after['translations/ru/auth.json'],
        isNot(before['translations/ru/auth.json']),
      );
    });

    test('a key with nowhere to go is reported, never guessed at', () {
      // An empty file has nothing to anchor against and no indentation to
      // copy. Inventing a layout for it would be the tool deciding how
      // someone's repository is arranged.
      final project = makeProject(
        translations: {'en.json': '{"a": "A"}', 'ru.json': '{}'},
        configYaml: interchangeConfigYaml,
      );
      final outcome = importCsv(
        project,
        Csv.encode([
          ['key', 'description', 'en', 'ru'],
          ['a', '', 'A', 'А'],
        ]),
        write: true,
      );

      final reported = outcome.diagnostics.singleWhere(
        (d) => d.code == 'unplaceable_key',
      );
      expect(reported.translationKey, 'a');
      expect(reported.details, contains('by hand once'));
      expect(project.translations['translations/ru.json'], '{}');
    });
  });

  group('reading what came back', () {
    test('an ARB bundle from a TMS', () {
      final project = makeProject(
        translations: {
          'en.json': '{"a": "A", "b": "B"}',
          'ru.json': '{"a": "А"}',
        },
        configYaml: interchangeConfigYaml,
      );
      final diagnostics = DiagnosticCollector();
      final bundle = InterchangeBundle.readArb(
        files: [
          (
            uri: Uri.parse('memory:/ru.arb'),
            content:
                '{"@@locale": "ru", "a": "А", "b": "Б", '
                '"@b": {"description": "ignored"}}',
          ),
        ],
        diagnostics: diagnostics,
      )!;
      final result = TranslationImporter.plan(
        catalog: project.catalog,
        bundle: bundle,
        diagnostics: diagnostics,
      );
      final ru = result.locales.single;
      expect(ru.localeTag, 'ru');
      expect(ru.added, 1);
      expect(ru.unchanged, 1);
    });

    test('a csv that is not one is refused with a span', () {
      final project = makeProject(
        translations: {'en.json': '{"a": "A"}'},
        configYaml: interchangeConfigYaml,
      );
      final outcome = importCsv(project, 'not,a,header\nrows,here,either\n');
      final reported = outcome.diagnostics.singleWhere(
        (d) => d.code == 'invalid_interchange',
      );
      expect(reported.severity, Severity.error);
      expect(reported.message, contains('must be named "key"'));
      expect(reported.span, isNotNull);
    });
  });

  group('the CLI', () {
    test(
      'writes nothing without --write, and says what it would do',
      () {
        // The one unforgivable behaviour: a command that rewrites someone's
        // translation files because they ran it to see what it would do.
        final project = copyFixture('json');
        final before = project.translations;
        File(p.join(project.root, 'hand_off.csv')).writeAsStringSync(
          Csv.encode([
            ['key', 'description', 'en', 'ru'],
            ['wallet.balance', '', 'Balance: {amount}', 'Остаток: {amount}'],
          ]),
        );

        final dry = runCli(project.root, ['import', '--from=hand_off.csv']);
        expect(dry.exitCode, 0, reason: '${dry.stdout}${dry.stderr}');
        expect('${dry.stdout}', contains('Dry run'));
        expect('${dry.stdout}', contains('Pass --write'));
        expect('${dry.stdout}', contains('Остаток: {amount}'));
        expect(
          project.translations,
          before,
          reason: 'a dry run must not write',
        );

        final wet = runCli(project.root, [
          'import',
          '--from=hand_off.csv',
          '--write',
        ]);
        expect(wet.exitCode, 0, reason: '${wet.stdout}${wet.stderr}');
        expect('${wet.stdout}', contains('wrote translations/ru.json'));
        expect(project.translations, isNot(before));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('what it writes still builds', () {
      final project = makeProject(
        translations: {
          'en.json': '{"a": "A", "b": "B"}',
          'ru.json': '{"a": "А"}',
        },
        configYaml: interchangeConfigYaml,
      );
      File(p.join(project.root, 'hand_off.csv')).writeAsStringSync(
        Csv.encode([
          ['key', 'description', 'en', 'ru'],
          ['a', '', 'A', 'А'],
          ['b', '', 'B', 'Б'],
        ]),
      );
      expect(runCli(project.root, ['analyze']).exitCode, isNot(0));

      final imported = runCli(project.root, [
        'import',
        '--from=hand_off.csv',
        '--write',
      ]);
      expect(imported.exitCode, 0, reason: '${imported.stdout}');
      final analyzed = runCli(project.root, ['analyze']);
      expect(
        analyzed.exitCode,
        0,
        reason: '${analyzed.stdout}${analyzed.stderr}',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'a --from that does not exist is refused',
      () {
        final project = copyFixture('json');
        final result = runCli(project.root, ['import', '--from=nowhere.csv']);
        expect(result.exitCode, 1);
        expect('${result.stderr}', contains('does not exist'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('import without --from says so', () {
      final project = copyFixture('json');
      final result = runCli(project.root, ['import']);
      expect(result.exitCode, 64);
      expect('${result.stderr}', contains('needs --from'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'a directory of bundles is read as ARB',
      () {
        final project = copyFixture('json');
        final out = runCli(project.root, [
          'export',
          '--format=arb',
          '--out=tms',
        ]);
        expect(out.exitCode, 0, reason: '${out.stdout}${out.stderr}');
        final before = project.translations;

        final result = runCli(project.root, ['import', '--from=tms']);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(
          '${result.stdout}',
          contains('Nothing to import'),
          reason: 'a round trip through arb changes nothing',
        );
        expect(project.translations, before);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
