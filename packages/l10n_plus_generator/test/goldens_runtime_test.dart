@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/formats/app_localizations.g.dart';
import 'goldens/split/app_localizations.g.dart' as split;

/// Runs the formatter surface golden instead of only reading it.
///
/// `dart analyze` already proves every generated call exists and type checks.
/// That is a different guarantee from producing the right string: `integer`
/// resolves whether or not it rounds, and a dropped `decimalDigits` compiles
/// perfectly. This is the same file, executed.
void main() {
  setUpAll(initializeAppLocalizationsFormatting);

  final en = AppLocalizations.forLocale(AppLocale.en);
  final ru = AppLocalizations.forLocale(AppLocale.ru);

  group('number styles', () {
    test('the default and decimal are the same grouping', () {
      expect(en.numberDefault(n: 1234.5), '1,234.5');
      expect(en.numberDecimal(n: 1234.5), '1,234.5');
      expect(ru.numberDecimal(n: 1234.5), '1 234,5');
    });

    test('integer rounds and keeps the grouping', () {
      // There is no `NumberFormat.integer`; this is the decimal pattern with
      // zero fraction digits, and only running it shows the rounding.
      expect(en.numberInteger(n: 1234.56), '1,235');
      expect(en.numberInteger(n: 1000), '1,000');
      expect(ru.numberInteger(n: 1234.56), '1 235');
    });

    test('percent multiplies by a hundred', () {
      expect(en.numberPercent(n: 0.42), '42%');
    });

    test('compact and compactLong shorten', () {
      expect(en.numberCompact(n: 1200000), '1.2M');
      expect(en.numberCompactLong(n: 1200000), '1.2 million');
    });

    test('scientific is scientific', () {
      expect(en.numberScientific(n: 1234), contains('E'));
    });

    test('decimalPercentPattern is percent with a digit count', () {
      // The reason it is a style of its own rather than an alias of
      // `percent`: `NumberFormat.decimalPercentPattern` is the constructor
      // that takes `decimalDigits`, and folding it onto `percentPattern`
      // would silently drop what a gen_l10n bundle asked for.
      // Undeclared, it is `percentPattern`: the digit count defaults to 0.
      expect(en.numberDecimalPercentPattern(n: 0.4256), '43%');
      // Declared, the digits are honoured — which is the whole point of the
      // constructor, and what folding it onto `percent` would have lost.
      expect(en.optPercent(n: 0.4256), '42.56%');
      // A non breaking space before the sign, which is what `ru` uses.
      expect(ru.optPercent(n: 0.4256), '42,56\u00a0%');
    });
  });

  group('currency styles', () {
    test('currency prints the ISO code, simpleCurrency the symbol', () {
      expect(en.numberCurrency(n: 1234.5), 'USD1,234.50');
      expect(en.numberSimpleCurrency(n: 1234.5), r'$1,234.50');
    });

    test('the compact pair abbreviates the amount', () {
      // `compactCurrency` prints the code, `compactSimpleCurrency` the
      // symbol, exactly as the non compact pair does.
      expect(en.numberCompactCurrency(n: 1200000), 'USD1.2M');
      expect(en.numberCompactSimpleCurrency(n: 1200000), r'$1.2M');
      expect(en.codeCompactCurrency(n: 1200000), 'USD1.2M');
      expect(en.codeCompactSimpleCurrency(n: 1200000), r'$1.2M');
    });

    test('an explicit code survives into another locale', () {
      expect(en.codeCurrency(n: 1234.5), 'USD1,234.50');
      expect(ru.codeCurrency(n: 1234.5), '1 234,50 USD');
      expect(ru.codeCurrency(n: 1234.5), isNot(contains('RUB')));
    });

    test('simpleCurrency with a code shows that currency symbol', () {
      expect(en.codeSimpleCurrency(n: 1234.5), r'$1,234.50');
      expect(ru.codeSimpleCurrency(n: 1234.5), '1 234,50 \$');
    });
  });

  group('declared currency settings', () {
    test('an explicit symbol replaces the code', () {
      // The declared symbol is `US$`; a `$` that survived into the generated
      // string literal unescaped would not have compiled.
      expect(en.optSymbol(n: 1234.5), r'US$1,234.50');
    });

    test('decimalDigits really drops the fraction', () {
      expect(en.optDigits(n: 1234.56), 'USD1,235');
      expect(en.optDigits(n: 1000), 'USD1,000');
    });

    test('a code, a symbol and eight digits together', () {
      expect(en.optAll(n: 1.23456789), 'B1.23456789');
    });

    test('simpleCurrency takes a code and digits', () {
      expect(en.optSimple(n: 1234.56), '¥1,235');
    });
  });

  group('per locale overrides', () {
    test('a bundle restyles what the base declared, keeping its digits', () {
      // Base: currency, no code, zero digits. Russian declares only
      // `"format": "simpleCurrency"` and inherits the rest.
      expect(en.optDigits(n: 1234.56), 'USD1,235');
      expect(ru.optDigits(n: 1234.56), '1 235 ₽');
    });

    test('the signature is the same in both locales', () {
      // Not an assertion the analyzer can skip: both calls type check against
      // one interface, so a per locale override that changed the parameter
      // type would fail to compile here.
      const double amount = 1234.56;
      final AppLocalizations Function(AppLocale) forLocale =
          AppLocalizations.forLocale;
      for (final locale in AppLocale.values) {
        expect(forLocale(locale).optDigits(n: amount), isNotEmpty);
      }
    });
  });

  group('a library split into one part per locale', () {
    // Analysis proves the parts link. This proves the library behaves: the
    // `const` implementations resolve across part boundaries, and each
    // locale's private formatters are reachable from its own part.
    test('the locale enum reaches every part', () {
      for (final locale in split.AppLocale.values) {
        expect(locale.translations.appLocale, locale);
      }
    });

    test('translations come from the right part', () {
      final en = split.AppLocalizations.forLocale(split.AppLocale.en);
      final ru = split.AppLocalizations.forLocale(split.AppLocale.ru);
      expect(en.auth.login.title, 'Log in');
      expect(ru.auth.login.title, 'Войти');
    });

    test('formatters declared in a part still run', () {
      final en = split.AppLocalizations.forLocale(split.AppLocale.en);
      final ru = split.AppLocalizations.forLocale(split.AppLocale.ru);
      expect(en.wallet.balance(amount: 1234.5), 'Balance: USD1,234.50');
      // The Russian part declares its own fraction digits.
      expect(ru.wallet.balance(amount: 1234.5), 'Баланс: 1\u00a0235\u00a0USD');
    });

    test('namespace access still allocates nothing', () {
      final en = split.AppLocalizations.forLocale(split.AppLocale.en);
      expect(identical(en.wallet, en.wallet), isTrue);
      expect(identical(en.auth.login, en.auth.login), isTrue);
    });
  });

  group('date and time styles', () {
    final at = DateTime(2026, 3, 14, 15, 45, 30);

    test('named date styles differ by locale', () {
      expect(en.date37(d: at), 'Mar 14, 2026'); // yMMMd
      expect(ru.date37(d: at), isNot(en.date37(d: at)));
      expect(ru.date37(d: at), contains('2026'));
    });

    test('a clock skeleton renders the time', () {
      // U+202F, the narrow no-break space ICU puts before the day period.
      expect(en.time05(t: at), '3:45\u202fPM'); // jm
      expect(ru.time05(t: at), '15:45');
    });

    test('a sample across the skeleton range renders', () {
      // Not exhaustive: the golden proves all of them compile, this checks
      // that a spread of them survive a real value in both locales.
      for (final render in <String Function()>[
        () => en.date00(d: at),
        () => en.date10(d: at),
        () => en.date30(d: at),
        () => ru.date00(d: at),
        () => ru.date30(d: at),
      ]) {
        expect(render(), isNotEmpty);
      }
    });
  });
}
