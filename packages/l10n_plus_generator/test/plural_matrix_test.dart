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
String _bundle(String language) => _message(
  'cat',
  'plural',
  CldrPluralRules.forLanguage(language)!.categories,
);

/// The same, on the ordinal table, which is a different and much smaller set
/// of languages.
String _ordinalBundle(String language) => _message(
  'ord',
  'selectordinal',
  CldrPluralRules.ordinalForLanguage(language)!.categories,
);

String _message(String key, String type, Set<PluralCategory> categories) {
  final branches = [
    for (final category in PluralCategory.values)
      if (category != PluralCategory.other && categories.contains(category))
        '${category.name}{${category.name}}',
    'other{other}',
  ].join(' ');
  return '{\n  "$key": "{count, $type, $branches}"\n}\n';
}

void main() {
  test('every language in the table generates its own CLDR branches', () {
    final languages = CldrPluralRules.supportedLanguages;
    final result = runGenerator({
      // English first: it is the base locale.
      'en.json': _bundle('en'),
      for (final language in languages)
        if (language != 'en') '$language.json': _bundle(language),
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

  test('every ordinal language generates its own CLDR branches', () {
    final languages = CldrPluralRules.supportedOrdinalLanguages;
    final result = runGenerator({
      'en.json': _ordinalBundle('en'),
      for (final language in languages)
        if (language != 'en') '$language.json': _ordinalBundle(language),
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

  test('the matrix covers every language the tables claim', () {
    for (final (fixture, languages) in [
      ('plurals', CldrPluralRules.supportedLanguages),
      ('ordinals', CldrPluralRules.supportedOrdinalLanguages),
    ]) {
      final golden = File(
        p.join(_packageRoot, 'test/goldens/$fixture/app_localizations.g.dart'),
      );
      if (!golden.existsSync()) continue;
      final source = golden.readAsStringSync();
      for (final language in languages) {
        expect(
          source,
          contains("L10nLocale('$language')"),
          reason: '$language is in the $fixture table but not executed.',
        );
      }
    }
  });
}
