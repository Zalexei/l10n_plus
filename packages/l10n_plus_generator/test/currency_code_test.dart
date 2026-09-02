import 'package:l10n_plus_generator/src/ast/message_ast.dart';
import 'package:l10n_plus_generator/src/codegen/intl_formatters.dart';
import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

const String _config = '''
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

/// Generated source with runs of whitespace collapsed.
///
/// `dart_style` wraps long constructor calls across lines, so assertions on
/// the emitted call would otherwise depend on where it decided to break.
String collapsed(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

String generated(Map<String, String> files) {
  final result = runGenerator(files, configYaml: _config);
  expect(
    errorsOf(result),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format(highlight: false)).join(),
  );
  return result.files.single.contents;
}

/// A one placeholder ARB bundle whose declaration is [declaration].
String _arb(String declaration) =>
    '{"@@locale": "en", "price": "{amount}", '
    '"@price": {"placeholders": {"amount": {"type": "double", $declaration}}}}';

/// The same, already formatted as a currency, with [optionalParameters].
String _currencyArb(String optionalParameters) =>
    _arb('"format": "currency", "optionalParameters": $optionalParameters');

void main() {
  group('currency:CODE in a message', () {
    test('an explicit code reaches NumberFormat.currency', () {
      final source = generated({
        'en.json': '{"price": "Price: {amount, number, currency:USD}"}',
      });
      expect(
        collapsed(source),
        contains(
          "_enNumberCurrencyUsd = NumberFormat.currency( "
          "locale: 'en', name: 'USD', );",
        ),
      );
      expect(source, contains(r'${_enNumberCurrencyUsd.format(amount)}'));
      expect(source, contains('String price({required num amount})'));
    });

    test('the code survives into a non default locale', () {
      final result = runGenerator({
        'en.json': '{"price": "{amount, number, currency:USD}"}',
        'ru.json': '{"price": "{amount, number, currency:USD}"}',
      }, configYaml: _config);
      expect(errorsOf(result), isEmpty);

      final source = collapsed(result.files.single.contents);
      expect(source, contains("locale: 'ru', name: 'USD'"));
      expect(source, contains('_ruNumberCurrencyUsd ='));
    });

    test('two currencies in one locale are two formatters', () {
      final source = generated({
        'en.json': '''
{
  "dollars": "{a, number, currency:USD}",
  "euros": "{b, number, currency:EUR}",
  "local": "{c, number, currency}"
}
''',
      });
      final text = collapsed(source);
      expect(
        text,
        contains(
          "_enNumberCurrencyUsd = NumberFormat.currency( "
          "locale: 'en', name: 'USD', );",
        ),
      );
      expect(
        text,
        contains(
          "_enNumberCurrencyEur = NumberFormat.currency( "
          "locale: 'en', name: 'EUR', );",
        ),
      );
      expect(
        text,
        contains("_enNumberCurrency = NumberFormat.currency(locale: 'en');"),
      );
    });

    test('the doc comment shows the code', () {
      final source = generated({
        'en.json': '{"price": "{amount, number, currency:JPY}"}',
      });
      expect(source, contains('{amount, number, currency:JPY}'));
    });

    test('a lower case code is rejected', () {
      final result = runGenerator({
        'en.json': '{"price": "{amount, number, currency:usd}"}',
      }, configYaml: _config);

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'icu_invalid_currency_code');
      expect(diagnostic.message, contains('usd'));
      expect(diagnostic.details, contains('three upper case letters'));
      expect(diagnostic.translationKey, 'price');
    });

    test('a code of the wrong length is rejected', () {
      final result = runGenerator({
        'en.json': '{"price": "{amount, number, currency:USDX}"}',
      }, configYaml: _config);
      expect(codesOf(result), ['icu_invalid_currency_code']);
    });

    test('a missing code is rejected', () {
      final result = runGenerator({
        'en.json': '{"price": "{amount, number, currency:}"}',
      }, configYaml: _config);

      final diagnostic = result.diagnostics.first;
      expect(diagnostic.code, 'icu_invalid_currency_code');
      expect(diagnostic.details, contains('currency:USD'));
    });

    test('a code on a style that is not currency is rejected', () {
      final result = runGenerator({
        'en.json': '{"share": "{value, number, percent:USD}"}',
      }, configYaml: _config);

      final diagnostic = result.diagnostics.first;
      expect(diagnostic.code, 'icu_unexpected_currency_code');
      expect(diagnostic.message, contains('percent'));
      expect(diagnostic.details, contains('Only currency and simpleCurrency'));
    });

    test('a code on a date style is rejected', () {
      final result = runGenerator({
        'en.json': '{"when": "{d, date, yMMMd:USD}"}',
      }, configYaml: _config);
      expect(codesOf(result), ['icu_unexpected_currency_code']);
    });

    test('an ICU number skeleton names the supported spelling', () {
      final result = runGenerator({
        'en.json': r'{"price": "{amount, number, ::currency/USD}"}',
      }, configYaml: _config);

      final diagnostic = result.diagnostics.first;
      expect(diagnostic.code, 'icu_invalid_style');
      expect(diagnostic.details, contains('skeletons are not supported'));
      expect(diagnostic.details, contains('currency:USD'));
    });

    test('locales may render different currencies, with a warning', () {
      final result = runGenerator({
        'en.json': '{"price": "{amount, number, currency:USD}"}',
        'ru.json': '{"price": "{amount, number, currency:RUB}"}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'format_style_mismatch');
      expect(diagnostic.details, contains('number, currency:USD'));
      expect(diagnostic.details, contains('number, currency:RUB'));

      final source = result.files.single.contents;
      expect(collapsed(source), contains("locale: 'en', name: 'USD'"));
      expect(collapsed(source), contains("locale: 'ru', name: 'RUB'"));
    });
  });

  group('ARB optionalParameters', () {
    test('"name" is read as the currency code, gen_l10n style', () {
      final source = generated({
        'app_en.arb': '''
{
  "@@locale": "en",
  "price": "Price: {amount}",
  "@price": {
    "placeholders": {
      "amount": {
        "type": "double",
        "format": "currency",
        "optionalParameters": {"name": "USD"}
      }
    }
  }
}
''',
      });
      expect(collapsed(source), contains("locale: 'en', name: 'USD'"));
      expect(source, contains('String price({required double amount})'));
    });

    test('the message may also carry the code, if they agree', () {
      final source = generated({
        'app_en.arb': '''
{
  "@@locale": "en",
  "price": "{amount, number, currency:USD}",
  "@price": {
    "placeholders": {
      "amount": {"optionalParameters": {"name": "USD"}}
    }
  }
}
''',
      });
      expect(collapsed(source), contains("locale: 'en', name: 'USD'"));
    });

    test('a disagreement between message and metadata is an error', () {
      final result = runGenerator({
        'app_en.arb': '''
{
  "@@locale": "en",
  "price": "{amount, number, currency:USD}",
  "@price": {
    "placeholders": {
      "amount": {"optionalParameters": {"name": "EUR"}}
    }
  }
}
''',
      }, configYaml: _config);

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'conflicting_currency_code');
      expect(diagnostic.details, contains('currency:USD'));
      expect(diagnostic.details, contains('EUR'));
    });

    test('a malformed code is rejected', () {
      final result = runGenerator({
        'app_en.arb': '''
{
  "@@locale": "en",
  "price": "{amount}",
  "@price": {
    "placeholders": {
      "amount": {"type": "double", "format": "currency",
                 "optionalParameters": {"name": "dollars"}}
    }
  }
}
''',
      }, configYaml: _config);

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'invalid_currency_code');
      expect(diagnostic.details, contains('found: dollars'));
    });

    test('a code without a currency format is rejected', () {
      final result = runGenerator({
        'app_en.arb': '''
{
  "@@locale": "en",
  "price": "{amount}",
  "@price": {
    "placeholders": {
      "amount": {"optionalParameters": {"name": "USD"}}
    }
  }
}
''',
      }, configYaml: _config);

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'unexpected_currency_code');
      expect(diagnostic.details, contains('"format": "currency"'));
    });

    test('a code on a plural argument is rejected', () {
      final result = runGenerator({
        'app_en.arb': '''
{
  "@@locale": "en",
  "items": "{count, plural, one{# item} other{# items}}",
  "@items": {
    "placeholders": {
      "count": {"optionalParameters": {"name": "USD"}}
    }
  }
}
''',
      }, configYaml: _config);
      expect(codesOf(result), ['unexpected_currency_code']);
    });

    test('customPattern is reported rather than passed through', () {
      final result = runGenerator({
        'app_en.arb': '''
{
  "@@locale": "en",
  "price": "{amount}",
  "@price": {
    "placeholders": {
      "amount": {"type": "double", "format": "currency",
                 "optionalParameters": {"name": "USD",
                                        "customPattern": "\u00a4#,##0.00"}}
    }
  }
}
''',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'unsupported_optional_parameter');
      expect(diagnostic.message, contains('customPattern'));
      expect(diagnostic.details, contains('name, symbol, decimalDigits'));
      expect(
        collapsed(result.files.single.contents),
        contains("locale: 'en', name: 'USD'"),
      );
    });

    test('a non object optionalParameters is a warning', () {
      final result = runGenerator({
        'app_en.arb': '''
{
  "@@locale": "en",
  "price": "{amount, number, currency}",
  "@price": {
    "placeholders": {
      "amount": {"optionalParameters": "USD"}
    }
  }
}
''',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      expect(codesOf(result), ['invalid_metadata']);
    });
  });

  group('simpleCurrency', () {
    test('renders the symbol constructor, with an explicit code', () {
      final source = generated({
        'en.json': '{"price": "{amount, number, simpleCurrency:USD}"}',
      });
      expect(
        collapsed(source),
        contains(
          "_enNumberSimpleCurrencyUsd = NumberFormat.simpleCurrency( "
          "locale: 'en', name: 'USD', );",
        ),
      );
    });

    test('works without a code, like currency does', () {
      final source = generated({
        'en.json': '{"price": "{amount, number, simpleCurrency}"}',
      });
      expect(
        collapsed(source),
        contains(
          "_enNumberSimpleCurrency = "
          "NumberFormat.simpleCurrency( locale: 'en', );",
        ),
      );
    });

    test('currency and simpleCurrency are separate formatters', () {
      final source = collapsed(
        generated({
          'en.json':
              '{"code": "{a, number, currency:USD}",'
              ' "symbol": "{b, number, simpleCurrency:USD}"}',
        }),
      );
      expect(source, contains('_enNumberCurrencyUsd ='));
      expect(source, contains('_enNumberSimpleCurrencyUsd ='));
    });

    test('ARB may name it as a format', () {
      final source = generated({
        'app_en.arb': _arb(
          '"format": "simpleCurrency", '
          '"optionalParameters": {"name": "EUR"}',
        ),
      });
      expect(
        collapsed(source),
        contains("NumberFormat.simpleCurrency( locale: 'en', name: 'EUR', )"),
      );
    });

    test('it is listed among the supported styles', () {
      final result = runGenerator({
        'en.json': '{"a": "{n, number, gazillions}"}',
      }, configYaml: _config);
      expect(result.diagnostics.single.details, contains('simpleCurrency'));
    });
  });

  group('symbol and decimalDigits', () {
    test('an explicit symbol reaches NumberFormat', () {
      final source = generated({'app_en.arb': _currencyArb('{"symbol": "₽"}')});
      expect(
        collapsed(source),
        contains("NumberFormat.currency( locale: 'en', symbol: '₽', )"),
      );
    });

    test('a symbol containing a dollar sign is escaped', () {
      // An unescaped `$` would generate an interpolation and fail to parse,
      // so reaching a formatted file at all is half the assertion.
      final source = generated({
        'app_en.arb': _currencyArb(r'{"symbol": "US$"}'),
      });
      expect(source, contains(r"symbol: 'US\$'"));
    });

    test('decimalDigits reaches NumberFormat', () {
      final source = generated({
        'app_en.arb': _currencyArb('{"name": "USD", "decimalDigits": 0}'),
      });
      expect(
        collapsed(source),
        contains(
          "NumberFormat.currency( locale: 'en', name: 'USD', "
          "decimalDigits: 0, )",
        ),
      );
    });

    test('decimalDigits written as a string is accepted', () {
      final source = generated({
        'app_en.arb': _currencyArb('{"decimalDigits": "3"}'),
      });
      expect(collapsed(source), contains('decimalDigits: 3'));
    });

    test('all three combine', () {
      final source = collapsed(
        generated({
          'app_en.arb': _currencyArb(
            '{"name": "BTC", "symbol": "B", "decimalDigits": 8}',
          ),
        }),
      );
      expect(
        source,
        contains(
          "NumberFormat.currency( locale: 'en', name: 'BTC', "
          "symbol: 'B', decimalDigits: 8, )",
        ),
      );
    });

    test('differing options are differing formatters', () {
      final result = runGenerator({
        'app_en.arb':
            '{"@@locale": "en",'
            ' "cents": "{a}",'
            ' "@cents": {"placeholders": {"a": {"type": "double",'
            ' "format": "currency",'
            ' "optionalParameters": {"name": "USD", "decimalDigits": 2}}}},'
            ' "whole": "{b}",'
            ' "@whole": {"placeholders": {"b": {"type": "double",'
            ' "format": "currency",'
            ' "optionalParameters": {"name": "USD", "decimalDigits": 0}}}}}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains('_enNumberCurrencyUsdDigits2'));
      expect(source, contains('_enNumberCurrencyUsdDigits0'));
    });

    test('a negative decimalDigits is rejected', () {
      final result = runGenerator({
        'app_en.arb': _currencyArb('{"decimalDigits": -1}'),
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'invalid_metadata');
      expect(diagnostic.message, contains('between 0 and 20'));
    });

    test('a fractional decimalDigits is rejected', () {
      final result = runGenerator({
        'app_en.arb': _currencyArb('{"decimalDigits": 1.5}'),
      }, configYaml: _config);
      expect(codesOf(result), contains('invalid_metadata'));
    });

    test('an empty symbol is rejected', () {
      final result = runGenerator({
        'app_en.arb': _currencyArb('{"symbol": ""}'),
      }, configYaml: _config);

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'invalid_metadata');
      expect(diagnostic.message, contains('non empty string'));
    });

    test('a symbol on simpleCurrency is rejected, not silently emitted', () {
      final result = runGenerator({
        'app_en.arb': _arb(
          '"format": "simpleCurrency", '
          '"optionalParameters": {"name": "USD", "symbol": "US\$"}',
        ),
      }, configYaml: _config);

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'unsupported_currency_option');
      expect(diagnostic.message, contains('simpleCurrency'));
      expect(diagnostic.details, contains('"format": "currency"'));
    });

    test('a symbol on simpleCurrency in a non base locale is rejected', () {
      final result = runGenerator({
        'en.json': '{"price": "{amount, number, simpleCurrency:USD}"}',
        'app_ru.arb':
            '{"@@locale": "ru", "price": "{amount, number, simpleCurrency:USD}",'
            ' "@price": {"placeholders": {"amount":'
            ' {"optionalParameters": {"symbol": "US\$"}}}}}',
      }, configYaml: _config);

      expect(errorsOf(result), ['unsupported_currency_option']);
    });

    test('options without a currency format are rejected', () {
      final result = runGenerator({
        'app_en.arb': _arb(
          '"format": "percent", '
          '"optionalParameters": {"decimalDigits": 1}',
        ),
      }, configYaml: _config);

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'unexpected_currency_code');
      expect(diagnostic.details, contains('1 digits'));
    });
  });

  group('per locale currency settings', () {
    /// A two locale project: JSON base, ARB translation carrying metadata.
    Map<String, String> project(String amountDeclaration) => {
      'en.json': '{"price": "Price: {amount, number, currency:USD}"}',
      'app_ru.arb':
          '{"@@locale": "ru", "price": "Цена: {amount, number, currency:USD}",'
          ' "@price": {"placeholders": {"amount": $amountDeclaration}}}',
    };

    test('a bundle may pin its own fraction digits', () {
      final result = runGenerator(
        project('{"optionalParameters": {"decimalDigits": 0}}'),
        configYaml: _config,
      );

      expect(errorsOf(result), isEmpty);
      final source = collapsed(result.files.single.contents);
      // The base keeps the currency default, Russian drops the kopecks.
      expect(
        source,
        contains(
          "_enNumberCurrencyUsd = NumberFormat.currency( "
          "locale: 'en', name: 'USD', );",
        ),
      );
      expect(
        source,
        contains(
          "_ruNumberCurrencyUsdDigits0 = "
          "NumberFormat.currency( locale: 'ru', name: 'USD', "
          "decimalDigits: 0, );",
        ),
      );
    });

    test('differing fraction digits are not worth a warning', () {
      final result = runGenerator(
        project('{"optionalParameters": {"decimalDigits": 0}}'),
        configYaml: _config,
      );
      // Roubles without kopecks beside dollars with cents is the point of the
      // feature, not a divergence to report.
      expect(codesOf(result), isEmpty);
    });

    test('a different currency is reported as a warning, not an error', () {
      final result = runGenerator(
        project('{"optionalParameters": {"name": "RUB"}}'),
        configYaml: _config,
      );

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.severity, Severity.warning);
      expect(diagnostic.code, 'currency_options_mismatch');
      expect(diagnostic.translationKey, 'price');
      expect(diagnostic.details, contains('USD'));
      expect(diagnostic.details, contains('RUB'));
    });

    test('a bundle may pin a different currency', () {
      final result = runGenerator(
        project('{"optionalParameters": {"name": "RUB"}}'),
        configYaml: _config,
      );

      expect(errorsOf(result), isEmpty);
      final source = collapsed(result.files.single.contents);
      expect(source, contains("locale: 'en', name: 'USD'"));
      expect(source, contains("locale: 'ru', name: 'RUB'"));
    });

    test('a bundle may add a symbol the base did not ask for', () {
      final result = runGenerator(
        project('{"optionalParameters": {"symbol": "\$"}}'),
        configYaml: _config,
      );

      expect(errorsOf(result), isEmpty);
      expect(result.files.single.contents, contains(r"symbol: '\$'"));
    });

    test('declaring exactly what the base declares changes nothing', () {
      final same = runGenerator(
        project('{"optionalParameters": {"name": "USD"}}'),
        configYaml: _config,
      );
      final silent = runGenerator({
        'en.json': '{"price": "Price: {amount, number, currency:USD}"}',
        'app_ru.arb':
            '{"@@locale": "ru", "price": "Цена: {amount, number, currency:USD}"}',
      }, configYaml: _config);

      expect(codesOf(same), isEmpty);
      expect(same.files.single.contents, silent.files.single.contents);
    });

    test('settings on an argument the base does not format are an error', () {
      final result = runGenerator({
        'en.json': '{"who": "Hello, {name}"}',
        'app_ru.arb':
            '{"@@locale": "ru", "who": "Привет, {name}",'
            ' "@who": {"placeholders": {"name":'
            ' {"optionalParameters": {"name": "USD"}}}}}',
      }, configYaml: _config);

      // The base locale renders this as a plain String, so no locale can turn
      // it into money on its own — that would change the generated type.
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'unexpected_placeholder_format');
      expect(diagnostic.message, contains('no way at all'));
      expect(diagnostic.details, contains('USD'));
    });

    test('a malformed code in a non base locale is an error', () {
      final result = runGenerator(
        project('{"optionalParameters": {"name": "roubles"}}'),
        configYaml: _config,
      );
      expect(errorsOf(result), ['invalid_currency_code']);
    });

    test('the base locale is unaffected by another locale metadata', () {
      final withMetadata = runGenerator(
        project('{"optionalParameters": {"decimalDigits": 0}}'),
        configYaml: _config,
      );
      final source = withMetadata.files.single.contents;
      expect(
        source,
        contains(r"'Price: ${_enNumberCurrencyUsd.format(amount)}'"),
      );
      expect(source, isNot(contains('_enNumberCurrencyUsdDigits0')));
    });
  });

  group('per locale format style', () {
    /// A JSON base whose message writes the placeholder plainly, so the base
    /// declaration is the only thing that formats it.
    Map<String, String> project(String ruDeclaration) => {
      'app_en.arb':
          '{"@@locale": "en", "price": "Price: {amount}",'
          ' "@price": {"placeholders": {"amount":'
          ' {"type": "double", "format": "currency",'
          ' "optionalParameters": {"name": "USD"}}}}}',
      'app_ru.arb':
          '{"@@locale": "ru", "price": "Цена: {amount}",'
          ' "@price": {"placeholders": {"amount": $ruDeclaration}}}',
    };

    test('a bundle may render the same currency in another style', () {
      final result = runGenerator(
        project('{"format": "simpleCurrency"}'),
        configYaml: _config,
      );

      expect(errorsOf(result), isEmpty);
      final source = collapsed(result.files.single.contents);
      // English prints the ISO code, Russian the symbol, and the currency and
      // the Dart type are the same in both.
      expect(
        source,
        contains(
          "_enNumberCurrencyUsd = NumberFormat.currency( "
          "locale: 'en', name: 'USD', );",
        ),
      );
      expect(
        source,
        contains(
          "_ruNumberSimpleCurrencyUsd = "
          "NumberFormat.simpleCurrency( locale: 'ru', name: 'USD', );",
        ),
      );
      expect(
        result.files.single.contents,
        contains('String price({required double amount})'),
      );
    });

    test('the style may be combined with the locale currency settings', () {
      final result = runGenerator(
        project(
          '{"format": "simpleCurrency", '
          '"optionalParameters": {"name": "JPY", "decimalDigits": 0}}',
        ),
        configYaml: _config,
      );

      expect(errorsOf(result), isEmpty);
      expect(
        collapsed(result.files.single.contents),
        contains(
          "NumberFormat.simpleCurrency(locale: 'ru', name: 'JPY', "
          "decimalDigits: 0)",
        ),
      );
      // Differing currencies are still worth saying out loud.
      expect(codesOf(result), ['currency_options_mismatch']);
    });

    test('a style of another kind is rejected', () {
      final result = runGenerator(
        project('{"format": "yMMMd"}'),
        configYaml: _config,
      );

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'unsupported_placeholder_format');
      expect(diagnostic.message, contains('number'));
      expect(diagnostic.details, contains('percent'));
    });

    test('an unknown style is rejected', () {
      final result = runGenerator(
        project('{"format": "gazillions"}'),
        configYaml: _config,
      );
      expect(errorsOf(result), ['unsupported_placeholder_format']);
    });

    test('the generated signature is the same in every locale', () {
      final result = runGenerator(
        project('{"type": "int", "format": "compact"}'),
        configYaml: _config,
      );

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      // The base declared `double`; the Russian bundle saying `int` cannot
      // change the shared signature, only how the value is rendered.
      expect(source, contains('String price({required double amount})'));
      expect(source, isNot(contains('required int amount')));
      expect(source, contains("NumberFormat.compact(locale: 'ru')"));
    });

    test('what the message writes beats what the metadata declares', () {
      final result = runGenerator({
        'app_en.arb': '{"@@locale": "en", "price": "Price: {amount, number}"}',
        'app_ru.arb':
            '{"@@locale": "ru", "price": "Цена: {amount, number, percent}",'
            ' "@price": {"placeholders": {"amount":'
            ' {"format": "simpleCurrency"}}}}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains("NumberFormat.percentPattern('ru')"));
      expect(source, isNot(contains('_ruNumberSimpleCurrency')));
      // The two locales genuinely render differently, which the existing
      // cross locale check already reports.
      expect(codesOf(result), contains('format_style_mismatch'));
    });

    test('declaring the base style again changes nothing', () {
      final restated = runGenerator(
        project('{"format": "currency"}'),
        configYaml: _config,
      );
      final silent = runGenerator({
        'app_en.arb':
            '{"@@locale": "en", "price": "Price: {amount}",'
            ' "@price": {"placeholders": {"amount":'
            ' {"type": "double", "format": "currency",'
            ' "optionalParameters": {"name": "USD"}}}}}',
        'app_ru.arb': '{"@@locale": "ru", "price": "Цена: {amount}"}',
      }, configYaml: _config);

      expect(codesOf(restated), isEmpty);
      expect(restated.files.single.contents, silent.files.single.contents);
    });
  });

  group('IntlFormatters', () {
    test('accepts only three upper case letters', () {
      expect(IntlFormatters.isValidCurrencyCode('USD'), isTrue);
      expect(IntlFormatters.isValidCurrencyCode('XBT'), isTrue);
      expect(IntlFormatters.isValidCurrencyCode('usd'), isFalse);
      expect(IntlFormatters.isValidCurrencyCode('US'), isFalse);
      expect(IntlFormatters.isValidCurrencyCode('USDD'), isFalse);
      expect(IntlFormatters.isValidCurrencyCode('US1'), isFalse);
      expect(IntlFormatters.isValidCurrencyCode(''), isFalse);
    });

    test('only the currency style accepts a code', () {
      const currency = ArgumentFormat(ArgumentFormatKind.number, 'currency');
      const percent = ArgumentFormat(ArgumentFormatKind.number, 'percent');
      const date = ArgumentFormat(ArgumentFormatKind.date, 'yMMMd');
      expect(IntlFormatters.acceptsCurrencyOptions(currency), isTrue);
      expect(IntlFormatters.acceptsCurrencyOptions(percent), isFalse);
      expect(IntlFormatters.acceptsCurrencyOptions(date), isFalse);
    });

    test('the code is part of the formatter identity', () {
      const usd = ArgumentFormat(
        ArgumentFormatKind.number,
        'currency',
        CurrencyOptions(code: 'USD'),
      );
      const eur = ArgumentFormat(
        ArgumentFormatKind.number,
        'currency',
        CurrencyOptions(code: 'EUR'),
      );
      expect(usd, isNot(eur));
      expect(usd.toString(), 'number, currency:USD');

      final usdBinding = IntlFormatters.bindingFor(
        format: usd,
        localeTag: 'en',
        localeDartName: 'en',
      )!;
      final eurBinding = IntlFormatters.bindingFor(
        format: eur,
        localeTag: 'en',
        localeDartName: 'en',
      )!;
      expect(usdBinding.fieldName, isNot(eurBinding.fieldName));
    });
  });
}
