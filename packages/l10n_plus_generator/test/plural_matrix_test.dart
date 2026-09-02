import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/src/ast/message_ast.dart';
import 'package:l10n_plus_generator/src/plural/cldr_plural_rules.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// Set `UPDATE_GOLDENS=1` to rewrite the expected file.
bool get _updateGoldens => Platform.environment['UPDATE_GOLDENS'] == '1';

final String _packageRoot = p.dirname(
  p.dirname(
    Isolate.resolvePackageUriSync(
      Uri.parse('package:l10n_plus_generator/l10n_plus_generator.dart'),
    )!.toFilePath(),
  ),
);

const String _config = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
flutter:
  enabled: false
''';

/// One message whose every branch renders the name of its own category.
///
/// The branch set is derived from [CldrPluralRules] rather than written out,
/// so a language added to the table joins the matrix automatically — and so
/// does the diff, which is what makes the golden worth reading.
String _bundle(String language, {required bool ordinal}) {
  final rules = ordinal
      ? CldrPluralRules.ordinalForLanguage(language)!
      : CldrPluralRules.forLanguage(language)!;
  final branches = [
    for (final category in PluralCategory.values)
      if (category != PluralCategory.other &&
          rules.categories.contains(category))
        '${category.name}{${category.name}}',
    'other{other}',
  ].join(' ');
  final type = ordinal ? 'selectordinal' : 'plural';
  return '{\n  "cat": "{count, $type, $branches}"\n}\n';
}

void main() {
  test('every language in the table generates its own CLDR branches', () {
    final languages = CldrPluralRules.supportedLanguages;
    final result = runGenerator({
      // English first: it is the base locale.
      'en.json': _bundle('en', ordinal: false),
      for (final language in languages)
        if (language != 'en')
          '$language.json': _bundle(language, ordinal: false),
    }, configYaml: _config);

    expect(
      result.diagnostics.map((d) => d.format(highlight: false)).join(),
      isEmpty,
      reason: 'The matrix is derived from the table, so it must be clean.',
    );

    final golden = File(
      p.join(_packageRoot, 'test/goldens/plurals/app_localizations.g.dart'),
    );
    final generated = result.files.single.contents;
    if (_updateGoldens) {
      golden.parent.createSync(recursive: true);
      golden.writeAsStringSync(generated);
      return;
    }

    expect(
      golden.existsSync(),
      isTrue,
      reason: 'Missing golden ${golden.path}. Run UPDATE_GOLDENS=1.',
    );
    expect(
      generated,
      golden.readAsStringSync(),
      reason:
          'The CLDR plural table changed. Run UPDATE_GOLDENS=1, then read '
          'the diff: every branch here is a rule someone will ship.',
    );
  });

  test('the matrix covers every language the table claims', () {
    final golden = File(
      p.join(_packageRoot, 'test/goldens/plurals/app_localizations.g.dart'),
    );
    if (!golden.existsSync()) return;
    final source = golden.readAsStringSync();
    for (final language in CldrPluralRules.supportedLanguages) {
      expect(
        source,
        contains("L10nLocale('$language')"),
        reason: '$language is in the table but not in the executed matrix.',
      );
    }
  });

  test('every language with ordinal rules generates its own branches', () {
    final languages = CldrPluralRules.supportedOrdinalLanguages;
    final result = runGenerator({
      'en.json': _bundle('en', ordinal: true),
      for (final language in languages)
        if (language != 'en')
          '$language.json': _bundle(language, ordinal: true),
    }, configYaml: _config);

    expect(
      result.diagnostics.map((d) => d.format(highlight: false)).join(),
      isEmpty,
      reason: 'The matrix is derived from the table, so it must be clean.',
    );

    final golden = File(
      p.join(_packageRoot, 'test/goldens/ordinals/app_localizations.g.dart'),
    );
    final generated = result.files.single.contents;
    if (_updateGoldens) {
      golden.parent.createSync(recursive: true);
      golden.writeAsStringSync(generated);
      return;
    }

    expect(
      golden.existsSync(),
      isTrue,
      reason: 'Missing golden ${golden.path}. Run UPDATE_GOLDENS=1.',
    );
    expect(
      generated,
      golden.readAsStringSync(),
      reason:
          'The CLDR ordinal table changed. Run UPDATE_GOLDENS=1, then read '
          'the diff: every branch here is a rule someone will ship.',
    );
  });

  test('a language with cardinal rules but no ordinal ones is deliberate', () {
    // Not an error: CLDR gives fewer languages an ordinal rule than a
    // cardinal one, and `unknown_ordinal_language` is the honest answer for
    // the rest. This pins the count so that adding a cardinal language
    // without thinking about its ordinal shows up in the diff.
    final withoutOrdinals = CldrPluralRules.supportedLanguages
        .where((l) => CldrPluralRules.ordinalForLanguage(l) == null)
        .toList();
    expect(withoutOrdinals, isEmpty, reason: withoutOrdinals.join(', '));
  });
}
