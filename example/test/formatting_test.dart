import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_plus_example/generated/app_localizations.g.dart';

void main() {
  setUpAll(initializeAppLocalizationsFormatting);

  test('numbers use the locale grouping and decimal separators', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    final ru = AppLocalizations.forLocale(AppLocale.ru);

    expect(en.wallet.total(amount: 1234.5), 'Total: 1,234.5');

    final russian = ru.wallet.total(amount: 1234.5);
    expect(russian, startsWith('Итого: 1'));
    expect(russian, endsWith('234,5'));
  });

  test('dates use the locale month names and order', () {
    final at = DateTime(2026, 3, 14);
    final en = AppLocalizations.forLocale(AppLocale.en);
    final ru = AppLocalizations.forLocale(AppLocale.ru);

    expect(en.wallet.statement(from: at), 'Statement from Mar 14, 2026');

    final russian = ru.wallet.statement(from: at);
    expect(russian, startsWith('Выписка от 14'));
    expect(russian, contains('2026'));
    expect(russian, isNot(en.wallet.statement(from: at)));
  });

  test(
    'ordinals use the ordinal rules, which differ from the cardinal ones',
    () {
      final en = AppLocalizations.forLocale(AppLocale.en);
      expect(en.wallet.rank(place: 1), '1st largest');
      expect(en.wallet.rank(place: 2), '2nd largest');
      expect(en.wallet.rank(place: 3), '3rd largest');
      expect(en.wallet.rank(place: 4), '4th largest');
      expect(en.wallet.rank(place: 11), '11th largest');
      expect(en.wallet.rank(place: 21), '21st largest');
      expect(en.wallet.rank(place: 22), '22nd largest');
      expect(en.wallet.rank(place: 113), '113th largest');

      // Russian has no ordinal categories, so everything is `other`.
      final ru = AppLocalizations.forLocale(AppLocale.ru);
      expect(ru.wallet.rank(place: 1), '1-й по величине');
      expect(ru.wallet.rank(place: 3), '3-й по величине');
    },
  );

  test('plural offset subtracts before selecting and before rendering', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    expect(en.wallet.likes(count: 0), 'Nobody likes this');
    expect(en.wallet.likes(count: 1), 'You like this');
    expect(en.wallet.likes(count: 2), 'You and 1 other like this');
    expect(en.wallet.likes(count: 3), 'You and 2 others like this');

    final ru = AppLocalizations.forLocale(AppLocale.ru);
    expect(ru.wallet.likes(count: 2), 'Вам и ещё 1 человеку нравится');
    expect(ru.wallet.likes(count: 3), 'Вам и ещё 2 людям нравится');
    expect(ru.wallet.likes(count: 6), 'Вам и ещё 5 людям нравится');
  });

  test('an explicit currency code renders that currency in every locale', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    final ru = AppLocalizations.forLocale(AppLocale.ru);

    expect(en.wallet.price(amount: 1234.5), 'Price: USD1,234.50');

    // The whole point of the feature: the amount keeps the grouping and the
    // decimal comma of the Russian locale, but stays in US dollars where the
    // locale default would have rendered roubles.
    final russian = ru.wallet.price(amount: 1234.5);
    expect(russian, startsWith('Цена: 1'));
    expect(russian, contains('234,50'));
    expect(russian, isNot(contains('RUB')));
  });

  test('without a code the locale currency is used', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    final ru = AppLocalizations.forLocale(AppLocale.ru);

    // `NumberFormat.currency` renders the ISO code rather than the symbol, so
    // "USD" and "RUB" here are intl's output, not a placeholder.
    expect(en.wallet.localPrice(amount: 10), 'Local price: USD10.00');
    expect(ru.wallet.localPrice(amount: 10), 'Местная цена: 10\u00a0RUB');
  });

  test('simpleCurrency renders the symbol instead of the ISO code', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    final ru = AppLocalizations.forLocale(AppLocale.ru);

    expect(en.wallet.symbolPrice(amount: 1234.5), r'Symbol price: $1,234.50');

    // Same currency, same symbol, Russian grouping and decimal comma.
    expect(
      ru.wallet.symbolPrice(amount: 1234.5),
      'Цена символом: 1\u00a0234,50\u00a0\$',
    );
  });

  test('currency and simpleCurrency differ only in what they print', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    expect(en.wallet.price(amount: 1234.5), contains('USD'));
    expect(en.wallet.symbolPrice(amount: 1234.5), contains(r'$'));
    expect(en.wallet.symbolPrice(amount: 1234.5), isNot(contains('USD')));
  });

  test('a bundle carries its own fraction digits', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    final ru = AppLocalizations.forLocale(AppLocale.ru);

    // Both messages say {amount, number, currency}; only the Russian bundle
    // declares decimalDigits: 0, and only Russian loses the kopecks.
    expect(en.wallet.localPrice(amount: 1234.5), 'Local price: USD1,234.50');
    expect(
      ru.wallet.localPrice(amount: 1234.5),
      'Местная цена: 1\u00a0235\u00a0RUB',
    );
  });

  test('a bundle carries its own symbol', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    final ru = AppLocalizations.forLocale(AppLocale.ru);

    // English takes the ISO code the message asked for; the Russian bundle
    // declares "US\$" to tell dollars from roubles, and the `\$` in that symbol
    // survives into the generated string literal.
    expect(en.wallet.price(amount: 1234.5), 'Price: USD1,234.50');
    expect(ru.wallet.price(amount: 1234.5), 'Цена: 1\u00a0234,50\u00a0US\$');
  });

  test('format_plural_numbers renders # with the locale number format', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    final ru = AppLocalizations.forLocale(AppLocale.ru);

    // Below the grouping threshold the flag makes no visible difference.
    expect(en.wallet.summary(count: 3), 'You have 3 cards linked');

    expect(en.wallet.summary(count: 1500), 'You have 1,500 cards linked');

    // Russian groups with a non breaking space, not a comma.
    expect(ru.wallet.summary(count: 1500), 'У вас привязано 1\u00a0500 карт');
  });

  test('# after an offset formats the adjusted value', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    expect(en.wallet.likes(count: 2001), 'You and 2,000 others like this');
  });

  test('the integer style rounds and still groups', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    final ru = AppLocalizations.forLocale(AppLocale.ru);

    // ICU's `integer` is the decimal pattern with no fraction digits. There is
    // no NumberFormat.integer, so this used to generate uncompilable code.
    expect(en.wallet.rounded(amount: 1234.56), 'Rounded: 1,235');
    expect(en.wallet.rounded(amount: 1000), 'Rounded: 1,000');
    expect(ru.wallet.rounded(amount: 1234.56), 'Округлённо: 1\u00a0235');
  });

  test('repeated calls reuse the shared formatter', () {
    final en = AppLocalizations.forLocale(AppLocale.en);
    expect(en.wallet.total(amount: 1000), 'Total: 1,000');
    expect(en.wallet.total(amount: 1000), 'Total: 1,000');
  });
}
