@TestOn('vm')
library;

import 'dart:io';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/interchange_fixture.dart';

/// The test the whole workflow stands on.
///
/// Export, import the export back into the project it came from, and the
/// translation files must be byte for byte what they were. Anything less and
/// the round trip is not a workflow: a translator who corrects one string
/// cannot be handed a diff that also reorders the file, re-quotes every
/// message and loses the comments — nobody can review that, so nobody will.
///
/// Byte identity is a stronger claim than "the strings still mean the same".
/// It is also the only one a test can make without re-implementing the
/// parsers to compare meanings, and it catches the whole class of quiet
/// damage: a changed quoting style, a normalized escape, a lost `\r\n`, a
/// re-indented group, a sorted key order.
void main() {
  // Every input format, and the layouts they come in. `json`, `yaml` and `arb`
  // are one file per locale; `split` is three files per locale across two
  // formats with `{namespace}` in the path; `fill_missing` is a project where
  // one locale has almost nothing, which is the state a translator is sent.
  const fixtures = ['json', 'yaml', 'arb', 'split', 'fill_missing'];

  for (final fixture in fixtures) {
    group('$fixture, exported and imported back', () {
      for (final format in InterchangeFormat.values) {
        test(
          'leaves every translation file byte identical via ${format.name}',
          () {
            final project = copyFixture(fixture);
            final before = project.translations;
            expect(before, isNotEmpty);

            final exported = TranslationExporter.export(
              catalog: project.catalog,
              format: format,
            );

            final diagnostics = DiagnosticCollector();
            final bundle = _read(exported, format, diagnostics);
            expect(
              diagnostics.diagnostics.where(
                (d) => d.severity == Severity.error,
              ),
              isEmpty,
              reason: 'the export should read back cleanly',
            );

            final result = TranslationImporter.plan(
              catalog: project.catalog,
              bundle: bundle,
              diagnostics: diagnostics,
            );

            // Nothing to write is the first half of the claim: every message
            // that came back matched what the file already said.
            expect(result.writes, isEmpty, reason: _describe(result));
            expect(result.hasErrors, isFalse);

            // And the files on disk are untouched, which is the other half —
            // a plan that writes nothing cannot have changed them, but the
            // check costs nothing and would catch a write that happened
            // somewhere other than through the plan.
            expect(project.translations, before);

            // Not vacuous: every message of every locale was compared.
            final compared = result.locales.fold<int>(
              0,
              (total, locale) =>
                  total + locale.unchanged + locale.messages.length,
            );
            expect(
              compared,
              _messageCount(project.catalog),
              reason:
                  'the round trip must have looked at every message, or '
                  '"nothing changed" means nothing',
            );
          },
        );
      }

      test('exports every message of every locale with its text intact', () {
        // The byte identity above would also hold if the export dropped
        // messages and the import skipped them. This is the independent
        // check: the text that comes out of the interchange file is the text
        // that went in, ICU and all.
        final project = copyFixture(fixture);
        final catalog = project.catalog;

        for (final format in InterchangeFormat.values) {
          final exported = TranslationExporter.export(
            catalog: catalog,
            format: format,
          );
          final bundle = _read(exported, format, DiagnosticCollector());
          for (final locale in catalog.locales) {
            for (final entry in catalog.entries) {
              final message = locale.messages[entry.key];
              final returned = bundle.entries.where(
                (e) => e.localeTag == locale.tag && e.key == entry.key,
              );
              if (message == null) {
                // Untranslated: the export says so by leaving it out, and
                // never by sending the base locale's text as a translation.
                expect(
                  returned,
                  isEmpty,
                  reason:
                      '${format.name}: ${locale.tag}/${entry.key} is '
                      'untranslated and must not come back translated',
                );
                continue;
              }
              expect(
                returned.map((e) => e.text),
                [message.raw],
                reason: '${format.name}: ${locale.tag}/${entry.key}',
              );
            }
          }
        }
      });
    });
  }

  group('the encoder writes the project\'s own literals', () {
    // Byte identity above is achieved by touching only the messages that
    // changed. That is correct, but on its own it would also pass if the
    // encoder were wrong, because it is never asked. This asks it: for every
    // message in every fixture, the literal the encoder produces is the
    // literal already in the file.
    //
    // The fixtures are hand written files in each format's ordinary style, so
    // this is a claim about matching how people actually write translations,
    // not about matching a canonical form of our own.
    for (final fixture in ['json', 'yaml', 'arb', 'split']) {
      test(fixture, () {
        final project = copyFixture(fixture);
        var checked = 0;
        for (final locale in project.catalog.locales) {
          for (final message in locale.messages.values) {
            final file = message.file;
            final span = message.leaf.valueSpan;
            final source = file.content.substring(
              span.start.offset,
              span.end.offset,
            );
            expect(
              TranslationEditor.encodeValue(file.format, message.raw),
              source,
              reason: '${file.relativePath}: ${message.key}',
            );
            checked++;
          }
        }
        expect(checked, greaterThan(0));
      });
    }
  });

  test('a changed message rewrites that message and nothing else', () {
    // The other side of byte identity: when something does change, exactly
    // the characters of that one value change.
    final project = copyFixture('json');
    final before = File(
      p.join(project.root, 'translations/ru.json'),
    ).readAsStringSync();

    final catalog = project.catalog;
    final result = TranslationImporter.plan(
      catalog: catalog,
      bundle: InterchangeBundle(
        localeTags: const ['ru'],
        entries: const [
          InterchangeEntry(
            localeTag: 'ru',
            key: 'wallet.balance',
            text: 'Остаток: {amount}',
          ),
        ],
      ),
      diagnostics: DiagnosticCollector(),
    );

    expect(result.writes, hasLength(1));
    final after = result.writes.single.contents;
    expect(
      after,
      before.replaceFirst('"Баланс: {amount}"', '"Остаток: {amount}"'),
    );
  });
}

/// Reads [exported] back, as `import` would read what a translator returned.
InterchangeBundle _read(
  ExportResult exported,
  InterchangeFormat format,
  DiagnosticCollector diagnostics,
) {
  switch (format) {
    case InterchangeFormat.csv:
      final file = exported.files.single;
      return InterchangeBundle.readCsv(
        content: file.contents,
        uri: Uri.parse('memory:/${file.name}'),
        diagnostics: diagnostics,
      )!;
    case InterchangeFormat.arb:
      return InterchangeBundle.readArb(
        files: [
          for (final file in exported.files)
            (uri: Uri.parse('memory:/${file.name}'), content: file.contents),
        ],
        diagnostics: diagnostics,
      )!;
  }
}

/// Every message of every locale, which is what a round trip must account for.
int _messageCount(TranslationCatalog catalog) => catalog.locales.fold(
  0,
  (total, locale) =>
      total +
      catalog.entries.where((e) => locale.messages.containsKey(e.key)).length,
);

String _describe(ImportResult result) => [
  for (final locale in result.locales)
    for (final message in locale.messages)
      '${locale.localeTag} ${message.key}: '
          '${message.before} -> ${message.after}',
].join('\n');
