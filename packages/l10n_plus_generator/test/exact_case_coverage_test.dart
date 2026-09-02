import 'package:l10n_plus_generator/src/ast/message_ast.dart';
import 'package:l10n_plus_generator/src/plural/cldr_plural_rules.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// An explicit `=N` branch can cover a whole CLDR category.
///
/// `gen_l10n` bundles are written `{count, plural, =0{none} =1{one} other{#}}`,
/// and English `one` is `i = 1 and v = 0` — true of 1 and of nothing else. The
/// `=1` branch therefore renders every value the category could ever select,
/// and reporting `one` as missing sent every imported ARB bundle to a warning
/// that had no fix.
const String _config = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

void main() {
  group('the category is covered', () {
    test('=1 covers English one', () {
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, =0{none} =1{one} other{# items}}"}',
      }, configYaml: _config);
      expect(codesOf(result), isEmpty);
    });

    test('=1 covers a language whose one is n = 1', () {
      // Turkish writes `one` as `n = 1` rather than `i = 1 and v = 0`; both
      // are true of exactly one value.
      expect(
        CldrPluralRules.forLanguage('tr')!.conditions[PluralCategory.one],
        '@n == 1',
      );
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, =1{one} other{# items}}"}',
        'tr.json': '{"n": "{count, plural, =1{bir} other{# adet}}"}',
      }, configYaml: _config);
      expect(codesOf(result), isEmpty);
    });

    test('=2 covers Hebrew two, and =0 =1 =2 cover Arabic', () {
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, one{one} other{# items}}"}',
        'he.json':
            '{"n": "{count, plural, =1{one} =2{two} '
            'one{one} other{# פריטים}}"}',
        'ar.json':
            '{"n": "{count, plural, =0{zero} =1{one} =2{two} '
            'few{few} many{many} other{# عناصر}}"}',
      }, configYaml: _config);
      expect(codesOf(result), isEmpty);
    });
  });

  group('the category is not covered', () {
    test('=1 does not cover Russian one, which 21 also selects', () {
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, =1{one} other{# items}}"}',
        'ru.json': '{"n": "{count, plural, =1{один} other{# штук}}"}',
      }, configYaml: _config);

      final missing = result.diagnostics.where(
        (d) => d.code == 'missing_plural_category',
      );
      expect(missing, isNotEmpty);
      expect(missing.first.message, contains('ru'));
      expect(missing.first.message, contains('one'));
    });

    test('=1 does not cover Hebrew one, which 0.5 also selects', () {
      // Hebrew `one` is `i = 1 and v = 0 or i = 0 and v != 0`, so a fraction
      // below one is singular too and `=1` leaves it uncovered.
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, one{one} other{# items}}"}',
        'he.json': '{"n": "{count, plural, =1{one} two{two} other{#}}"}',
      }, configYaml: _config);

      expect(codesOf(result), contains('missing_plural_category'));
    });

    test('=1 does not cover a range category', () {
      // Arabic `few` is `n % 100 = 3..10`; no single `=N` closes it.
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, one{one} other{# items}}"}',
        'ar.json':
            '{"n": "{count, plural, =0{zero} =1{one} =2{two} '
            'many{many} other{#}}"}',
      }, configYaml: _config);

      final missing = result.diagnostics.firstWhere(
        (d) => d.code == 'missing_plural_category',
      );
      expect(missing.message, contains('few'));
      expect(missing.message, isNot(contains('zero')));
    });

    test('an offset breaks the argument, so nothing is covered', () {
      // With `offset:1`, `=1` matches an input of 1 while the categories see
      // 0. The two are about different numbers, so one cannot cover the other.
      final result = runGenerator({
        'en.json':
            '{"n": "{count, plural, offset:1 =1{you} other{you and # more}}"}',
      }, configYaml: _config);

      expect(codesOf(result), contains('missing_plural_category'));
    });
  });

  group('the rule table knows which categories are a single value', () {
    test('reads them off the generated conditions', () {
      final en = CldrPluralRules.forLanguage('en')!;
      expect(en.exactValueOf(PluralCategory.one), 1);

      final ar = CldrPluralRules.forLanguage('ar')!;
      expect(ar.exactValueOf(PluralCategory.zero), 0);
      expect(ar.exactValueOf(PluralCategory.one), 1);
      expect(ar.exactValueOf(PluralCategory.two), 2);
      expect(ar.exactValueOf(PluralCategory.few), isNull);
      expect(ar.exactValueOf(PluralCategory.many), isNull);

      final ru = CldrPluralRules.forLanguage('ru')!;
      expect(ru.exactValueOf(PluralCategory.one), isNull);

      // `hi` is `i = 0 or n = 1`: two values, so neither `=0` nor `=1` alone
      // closes it.
      expect(
        CldrPluralRules.forLanguage('hi')!.exactValueOf(PluralCategory.one),
        isNull,
      );
    });

    test('other is never a single value', () {
      for (final language in CldrPluralRules.supportedLanguages) {
        expect(
          CldrPluralRules.forLanguage(
            language,
          )!.exactValueOf(PluralCategory.other),
          isNull,
          reason: language,
        );
      }
    });
  });
}
