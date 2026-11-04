import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus/l10n_plus.dart';
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
# These fixtures exist to exercise plural tables, and some of the
# languages they reach are written right to left. The warning about
# `bidi_isolation` is about the application's text, which is not what
# is under test here.
ignore_diagnostics: [bidi_isolation_off]
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

/// A CLDR table key as a translation file name.
///
/// CLDR writes a qualified key with a hyphen (`pt-PT`); translation files are
/// named the way the generator reads them back, with an underscore.
String _fileTag(String tag) => L10nLocale.parse(tag).toFileTag();

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
  test('every entry in the table generates its own CLDR branches', () {
    final tags = CldrPluralRules.cardinalTags;
    final result = runGenerator({
      // English first: it is the base locale.
      'en.json': _bundle('en'),
      for (final tag in tags)
        if (tag != 'en') '${_fileTag(tag)}.json': _bundle(tag),
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

  test('every ordinal entry generates its own CLDR branches', () {
    final tags = CldrPluralRules.ordinalTags;
    final result = runGenerator({
      'en.json': _ordinalBundle('en'),
      for (final tag in tags)
        if (tag != 'en') '${_fileTag(tag)}.json': _ordinalBundle(tag),
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

  test('the matrix covers every entry the tables claim', () {
    for (final (fixture, tags) in [
      ('plurals', CldrPluralRules.cardinalTags),
      ('ordinals', CldrPluralRules.ordinalTags),
    ]) {
      final golden = File(
        p.join(_packageRoot, 'test/goldens/$fixture/app_localizations.g.dart'),
      );
      if (!golden.existsSync()) continue;
      final source = golden.readAsStringSync();
      for (final tag in tags) {
        expect(
          source,
          contains(_localeLiteral(tag)),
          reason: '$tag is in the $fixture table but not executed.',
        );
      }
    }
  });
}

/// The locale literal the emitter writes for [tag], to search the golden for.
///
/// Spelled out rather than asserted as a bare language code: `pt-PT` reaches
/// the generated file as `L10nLocale('pt', country: 'PT')`, and a search for
/// the language alone would pass while nothing executed its rules.
String _localeLiteral(String tag) {
  final locale = L10nLocale.parse(tag);
  final buffer = StringBuffer("L10nLocale('${locale.language}'");
  if (locale.script != null) buffer.write(", script: '${locale.script}'");
  if (locale.country != null) buffer.write(", country: '${locale.country}'");
  return (buffer..write(')')).toString();
}
