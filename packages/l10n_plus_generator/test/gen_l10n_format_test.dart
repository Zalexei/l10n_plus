import 'package:l10n_plus_generator/src/codegen/intl_formatters.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// The format names `gen_l10n` writes.
///
/// The README promises an ARB bundle exported from `gen_l10n` generates
/// without editing a message, and `"format": "decimalPattern"` — its spelling
/// of the plain decimal format — was met with `unsupported_placeholder_format`
/// instead. The names are folded onto the styles that already existed, so a
/// bundle using both spellings still gets one formatter.
const String _config = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

String _arb(String format) =>
    '{"@@locale": "en", "n": "{v}", '
    '"@n": {"placeholders": {"v": '
    '{"type": "double", "format": "$format"}}}}';

String _icu(String style) => '{"n": "{v, number, $style}"}';

void main() {
  group('aliases generate what the canonical name generates', () {
    for (final entry in IntlFormatters.numberStyleAliases.entries) {
      test('${entry.key} is ${entry.value}, in ARB metadata', () {
        final alias = runGenerator({
          'app_en.arb': _arb(entry.key),
        }, configYaml: _config);
        final canonical = runGenerator({
          'app_en.arb': _arb(entry.value),
        }, configYaml: _config);

        expect(errorsOf(alias), isEmpty);
        expect(alias.files.single.contents, canonical.files.single.contents);
      });

      test('${entry.key} is ${entry.value}, in the message', () {
        final alias = runGenerator({
          'en.json': _icu(entry.key),
        }, configYaml: _config);
        final canonical = runGenerator({
          'en.json': _icu(entry.value),
        }, configYaml: _config);

        expect(errorsOf(alias), isEmpty);
        expect(alias.files.single.contents, canonical.files.single.contents);
      });
    }

    test('both spellings in one project share one formatter', () {
      // The failure this rules out: `decimal` and `decimalPattern` emitting
      // `_enNumberDecimalPattern` twice, which does not compile, or under two
      // names, which builds a `NumberFormat` the project did not need.
      final result = runGenerator({
        'en.json':
            '{"a": "{v, number, decimal}", "b": "{v, number, decimalPattern}"}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(
        'NumberFormat.decimalPattern'.allMatches(source),
        hasLength(1),
        reason: source,
      );
    });

    test('a locale may restyle with an alias', () {
      final result = runGenerator({
        'app_en.arb':
            '{"@@locale": "en", "n": "{v}", '
            '"@n": {"placeholders": {"v": '
            '{"type": "double", "format": "decimal"}}}}',
        'app_ru.arb':
            '{"@@locale": "ru", "n": "{v}", '
            '"@n": {"placeholders": {"v": {"format": "decimalPattern"}}}}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      // Same style under another name is not a restyle, so the Russian
      // implementation reads the same formatter rather than declaring one.
      final source = result.files.single.contents;
      expect('NumberFormat.decimalPattern'.allMatches(source), hasLength(2));
    });
  });

  group('the compact currency pair', () {
    test('both generate, and only one takes a symbol', () {
      final result = runGenerator({
        'app_en.arb':
            '{"@@locale": "en", '
            '"a": "{v}", "@a": {"placeholders": {"v": {"type": "double", '
            '"format": "compactCurrency", "optionalParameters": '
            '{"name": "USD", "symbol": "\$", "decimalDigits": 1}}}}, '
            '"b": "{v}", "@b": {"placeholders": {"v": {"type": "double", '
            '"format": "compactSimpleCurrency", "optionalParameters": '
            '{"name": "JPY"}}}}}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains('NumberFormat.compactCurrency('));
      expect(source, contains('NumberFormat.compactSimpleCurrency('));
      expect(source, contains('decimalDigits: 1'));
    });

    test('compactSimpleCurrency refuses an explicit symbol', () {
      // `NumberFormat.compactSimpleCurrency` has no `symbol:` parameter, the
      // same reason `simpleCurrency` has none: deriving it is the difference.
      final result = runGenerator({
        'app_en.arb':
            '{"@@locale": "en", "a": "{v}", '
            '"@a": {"placeholders": {"v": {"type": "double", '
            '"format": "compactSimpleCurrency", '
            '"optionalParameters": {"symbol": "\$"}}}}}',
      }, configYaml: _config);

      expect(errorsOf(result), contains('unsupported_currency_option'));
    });

    test('a currency code works in the message too', () {
      final result = runGenerator({
        'en.json': '{"a": "{v, number, compactCurrency:USD}"}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      expect(result.files.single.contents, contains("name: 'USD'"));
    });
  });

  group('decimalPercentPattern', () {
    test('is its own style, not a spelling of percent', () {
      // Folding it onto `percent` would compile and would quietly drop the
      // digits, which is the one thing the constructor exists for.
      expect(
        IntlFormatters.numberStyleAliases.containsKey('decimalPercentPattern'),
        isFalse,
      );
      final result = runGenerator({
        'en.json': '{"a": "{v, number, decimalPercentPattern}"}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      expect(
        result.files.single.contents,
        contains('NumberFormat.decimalPercentPattern('),
      );
    });

    test('takes decimalDigits without being money', () {
      final result = runGenerator({
        'app_en.arb':
            '{"@@locale": "en", "a": "{v}", '
            '"@a": {"placeholders": {"v": {"type": "double", '
            '"format": "decimalPercentPattern", '
            '"optionalParameters": {"decimalDigits": 2}}}}}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      expect(result.files.single.contents, contains('decimalDigits: 2'));
    });

    test('refuses a currency code', () {
      final result = runGenerator({
        'app_en.arb':
            '{"@@locale": "en", "a": "{v}", '
            '"@a": {"placeholders": {"v": {"type": "double", '
            '"format": "decimalPercentPattern", '
            '"optionalParameters": {"name": "USD"}}}}}',
      }, configYaml: _config);

      expect(errorsOf(result), contains('unexpected_currency_code'));
    });

    test(
      'decimalDigits on a style that cannot take them is still an error',
      () {
        final result = runGenerator({
          'app_en.arb':
              '{"@@locale": "en", "a": "{v}", '
              '"@a": {"placeholders": {"v": {"type": "double", '
              '"format": "scientific", '
              '"optionalParameters": {"decimalDigits": 2}}}}}',
        }, configYaml: _config);

        final diagnostic = result.diagnostics.firstWhere(
          (d) => d.code == 'unexpected_currency_code',
        );
        expect(diagnostic.message, contains('decimalDigits'));
        expect(diagnostic.details, contains('decimalPercentPattern'));
      },
    );
  });
}
