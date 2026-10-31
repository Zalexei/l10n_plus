@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/fixture.dart';

const String _config = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

String _plural(String format, {String extra = ''}) =>
    '{"@@locale": "en", '
    '"cards": "{count, plural, one{# card} other{# cards}}", '
    '"@cards": {"placeholders": {"count": '
    '{"type": "num", "format": "$format"$extra}}}}';

String _generate(Map<String, String> files, {String configYaml = _config}) {
  final result = runGenerator(files, configYaml: configYaml);
  expect(
    errorsOf(result),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format(highlight: false)).join(),
  );
  return result.files.single.contents;
}

void main() {
  group('a format declared on a plural count', () {
    test('renders the count, and says nothing about dropping it', () {
      final result = runGenerator({
        'en.arb': _plural('currency'),
      }, configYaml: _config);

      expect(codesOf(result), isNot(contains('dropped_placeholder_format')));
      expect(errorsOf(result), isEmpty);
      expect(
        result.files.single.contents,
        contains(r"return '${_enNumberCurrency.format(count)} cards';"),
      );
    });

    test('the operands come from that formatter, not from the value', () {
      // The whole point. A currency renders `1` as `USD1.00`, so the operands
      // have to be read off two visible fraction digits, or English picks
      // `one` and prints "USD1.00 card".
      expect(
        _generate({'en.arb': _plural('currency')}),
        contains(
          'final \$operands = PluralOperands.formatted(\n'
          '      count,\n'
          '      minimumFractionDigits: _enNumberCurrency.minimumFractionDigits,\n'
          '      maximumFractionDigits: _enNumberCurrency.maximumFractionDigits,\n'
          '    );',
        ),
      );
    });

    test(
      'the bounds are read at run time, because a currency decides them',
      () {
        // `NumberFormat.currency` takes its fraction digits from the currency,
        // which the generator does not know: JPY has none, USD has two. Baking
        // a constant in here would be wrong for every bundle that names a
        // currency the default locale does not use.
        final source = _generate({'en.arb': _plural('currency')});
        expect(source, isNot(contains('minimumFractionDigits: 2')));
        expect(source, contains('_enNumberCurrency.minimumFractionDigits'));
      },
    );

    test('a count nobody declared still reads its own value', () {
      final source = _generate({
        'en.json': '{"cards": "{count, plural, one{# card} other{# cards}}"}',
      });
      expect(source, contains(r'PluralOperands(count)'));
      expect(source, isNot(contains('PluralOperands.formatted')));
    });

    test('format_plural_numbers takes its operands from its own pattern', () {
      // Consistency is the rule, not a special case for declared formats: if
      // `#` renders through the decimal pattern then that pattern decides the
      // visible digits, and it rounds to three where a `num` may carry more.
      final source = _generate({
        'en.json': '{"cards": "{count, plural, one{# card} other{# cards}}"}',
      }, configYaml: '$_config\nformat_plural_numbers: true\n');
      expect(source, contains('_enNumberDecimalPattern.minimumFractionDigits'));
    });

    test('a declared format beats format_plural_numbers', () {
      final source = _generate({
        'en.arb': _plural('percent'),
      }, configYaml: '$_config\nformat_plural_numbers: true\n');
      expect(source, contains('_enNumberPercentPattern.format(count)'));
      expect(source, isNot(contains('_enNumberDecimalPattern')));
    });

    test('currency options on the count are honoured too', () {
      final source = _generate({
        'en.arb': _plural(
          'currency',
          extra: ', "optionalParameters": {"decimalDigits": 0}',
        ),
      });
      expect(source, contains('decimalDigits: 0'));
      expect(source, contains('PluralOperands.formatted'));
    });

    test('an offset is formatted and read the same way', () {
      final source = _generate({
        'en.arb':
            '{"@@locale": "en", '
            '"likes": "{count, plural, offset:1 '
            'one{You and # other} other{You and # others}}", '
            '"@likes": {"placeholders": {"count": '
            '{"type": "num", "format": "decimalPattern"}}}}',
      });
      expect(source, contains(r'final $countOffset = count - 1;'));
      expect(source, contains(r'_enNumberDecimalPattern.format($countOffset)'));
      expect(
        source,
        contains('PluralOperands.formatted(\n      \$countOffset,'),
      );
    });

    test('each locale reads its own formatter', () {
      final source = _generate({
        'en.arb': _plural('currency'),
        'ru.arb':
            '{"@@locale": "ru", '
            '"cards": "{count, plural, one{# карта} few{# карты} '
            'many{# карт} other{# карты}}", '
            '"@cards": {"placeholders": {"count": '
            '{"type": "num", "format": "currency"}}}}',
      });
      expect(source, contains('_enNumberCurrency.minimumFractionDigits'));
      expect(source, contains('_ruNumberCurrency.minimumFractionDigits'));
    });

    test('a currency code needs a currency format to spend it on', () {
      // Unchanged for a bare code: there is no formatter to carry it, and
      // money rendered in the wrong currency is the failure being prevented.
      final bare = runGenerator({
        'en.arb': _plural(
          'decimalPattern',
          extra: ', "optionalParameters": {"name": "EUR"}',
        ),
      }, configYaml: _config);
      expect(codesOf(bare), contains('unexpected_currency_code'));

      // With one, the count is money like any other money argument.
      final declared = _generate({
        'en.arb': _plural(
          'currency',
          extra: ', "optionalParameters": {"name": "EUR"}',
        ),
      });
      expect(declared, contains('_enNumberCurrencyEur'));
      expect(declared, contains("name: 'EUR'"));
    });

    test('output stays deterministic', () {
      expect(
        _generate({'en.arb': _plural('currency')}),
        _generate({'en.arb': _plural('currency')}),
      );
    });
  });

  group('a format declared on a select argument', () {
    test('is still reported, because there is no number to format', () {
      final result = runGenerator({
        'en.arb':
            '{"@@locale": "en", "g": "{g, select, a{A} other{B}}", '
            '"@g": {"placeholders": {"g": '
            '{"type": "String", "format": "compactLong"}}}}',
      }, configYaml: _config);

      expect(codesOf(result), contains('dropped_placeholder_format'));
      expect(errorsOf(result), isEmpty);
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'dropped_placeholder_format',
      );
      expect(diagnostic.message, contains('"g"'));
      expect(diagnostic.details, contains('compactLong'));
      expect(diagnostic.translationKey, 'g');
    });

    test('it stays a warning, so a gen_l10n bundle still builds', () {
      final result = runGenerator(
        {
          'en.arb':
              '{"@@locale": "en", "g": "{g, select, a{A} other{B}}", '
              '"@g": {"placeholders": {"g": '
              '{"type": "String", "format": "compactLong"}}}}',
        },
        configYaml:
            '$_config\nignore_diagnostics: [dropped_placeholder_format]\n',
      );

      expect(codesOf(result), isNot(contains('dropped_placeholder_format')));
      expect(errorsOf(result), isEmpty);
    });
  });
}
