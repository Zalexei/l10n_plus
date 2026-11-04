import 'package:intl/intl.dart';
import 'package:l10n_plus/l10n_plus.dart';
import 'package:l10n_plus_generator/src/plural/cldr_plural_rules.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `pt` and `pt-PT` disagree about zero, and CLDR says so itself.
///
/// European Portuguese counts `one` for 1 alone, Brazilian Portuguese for 0
/// and 1 both. CLDR publishes that as a region qualified entry, the only one
/// in the cardinal table whose rules are not its language's.
const String _config = '''
input_directory: translations
output_directory: lib/generated
base_locale: pt_PT
fallback_locale: pt_PT
class_name: AppLocalizations
locale_enum_name: AppLocale
flutter:
  enabled: false
''';

/// All three categories `pt-PT` declares, so nothing is reported as missing.
const String _bundle = '''
{
  "items": "{count, plural, one{# item} many{# de itens} other{# itens}}"
}
''';

String _sourceOf(Map<String, String> translations, {String config = _config}) {
  final result = runGenerator(translations, configYaml: config);
  expect(errorsOf(result), isEmpty);
  return result.files.map((file) => file.contents).join('\n');
}

void main() {
  group('a region qualified locale uses its own CLDR rules', () {
    test('pt_PT counts one for 1 alone, not for 0 as well', () {
      final source = _sourceOf({'pt_PT.json': _bundle});

      // `i = 1 and v = 0` is pt-PT's `one`; `i = 0..1` is pt's.
      expect(source, contains('.i == 1 && '));
      expect(source, isNot(contains('.i >= 0 && ')));
    });

    test('pt and pt_BR still count one for 0 and 1', () {
      final source = _sourceOf({
        'pt.json': _bundle,
        'pt_BR.json': _bundle,
      }, config: _config.replaceAll('pt_PT', 'pt'));

      expect(source, contains('.i >= 0 && '));
      expect(source, isNot(contains('.i == 1 && ')));
    });

    test('the missing category warning names the rules it used', () {
      final result = runGenerator({
        'pt_PT.json':
            '{"items": "{count, plural, one{# item} other{# itens}}"}',
      }, configYaml: _config);

      final warning = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_plural_category',
      );
      expect(warning.details, contains('pt-PT uses:'));
      expect(warning.details, isNot(contains('pt uses:')));
    });
  });

  test('package:intl, asked in its own spelling, says the same', () {
    // The independent oracle `plural_matrix_runtime_test` runs the whole
    // matrix against. It carries its own copy of the CLDR data and keys it
    // the way a locale is written on a file, so it can be asked directly
    // whether zero is `one` in Portugal.
    String category(String locale, num n) => Intl.pluralLogic<String>(
      n,
      zero: 'zero',
      one: 'one',
      two: 'two',
      few: 'few',
      many: 'many',
      other: 'other',
      locale: locale,
      useExplicitNumberCases: false,
    );

    expect(category('pt_PT', 0), 'other');
    expect(category('pt', 0), 'one');
    expect(category('pt_BR', 0), 'one');
  });

  group('the lookup walks the locale lineage', () {
    test('pt_PT finds its own entry, pt_BR falls back to the language', () {
      expect(
        CldrPluralRules.cardinalFor(L10nLocale.parse('pt_PT'))?.tag,
        'pt-PT',
      );
      expect(CldrPluralRules.cardinalFor(L10nLocale.parse('pt_BR'))?.tag, 'pt');
      expect(CldrPluralRules.cardinalFor(L10nLocale.parse('pt'))?.tag, 'pt');
    });

    test('a region CLDR does not publish separately takes the language', () {
      // CLDR's parentLocales make pt-MZ inherit pt-PT, which this lookup does
      // not read: a region without its own entry takes its language's rules.
      expect(CldrPluralRules.cardinalFor(L10nLocale.parse('pt_MZ'))?.tag, 'pt');
      expect(CldrPluralRules.cardinalFor(L10nLocale.parse('ru_UA'))?.tag, 'ru');
    });

    test('a language CLDR has no rules for is still unknown', () {
      expect(CldrPluralRules.cardinalFor(L10nLocale.parse('zzz')), isNull);
    });

    test('ordinals resolve the same way', () {
      expect(CldrPluralRules.ordinalFor(L10nLocale.parse('en_GB'))?.tag, 'en');
      expect(CldrPluralRules.ordinalFor(L10nLocale.parse('pt_PT'))?.tag, 'pt');
    });
  });
}
