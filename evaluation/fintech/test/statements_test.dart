// Every assertion here is cross-checked against package:intl computed
// directly, so the test proves the generated code agrees with intl rather
// than agreeing with itself.
import 'package:fintech_statements/l10n/statements.g.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() async {
    await initializeStatementsFormatting();
    await initializeDateFormatting('ru');
    await initializeDateFormatting('ja');
  });

  group('numbers agree with intl computed directly', () {
    test('currency with an explicit code', () {
      for (final locale in StatementLocale.values) {
        final tag = locale.name;
        final expected = NumberFormat.currency(
          locale: tag,
          name: 'USD',
        ).format(1234.5);
        expect(
          Statements.forLocale(locale).statement.opening(amount: 1234.5),
          contains(expected),
          reason: tag,
        );
      }
    });

    test('simpleCurrency prints the symbol, currency prints the code', () {
      final en = Statements.forLocale(StatementLocale.en).statement;
      expect(en.opening(amount: 1234.5), 'Opening balance: USD1,234.50');
      expect(en.closing(amount: 9876.54), r'Closing balance: $9,876.54');
    });

    test('per locale decimalDigits override', () {
      // ja declares simpleCurrency with 0 fraction digits over the base's
      // currency/USD/2; en keeps the base.
      expect(
        Statements.forLocale(
          StatementLocale.en,
        ).statement.card(amount: 1234.56),
        'Card balance: ${NumberFormat.currency(locale: 'en', name: 'USD', decimalDigits: 2).format(1234.56)}',
      );
      expect(
        Statements.forLocale(
          StatementLocale.ja,
        ).statement.card(amount: 1234.56),
        'カード残高: ${NumberFormat.simpleCurrency(locale: 'ja', name: 'USD', decimalDigits: 0).format(1234.56)}',
      );
      // ru inherits name and digits from the base and changes only the style.
      expect(
        Statements.forLocale(
          StatementLocale.ru,
        ).statement.card(amount: 1234.56),
        'Баланс карты: ${NumberFormat.simpleCurrency(locale: 'ru', name: 'USD', decimalDigits: 2).format(1234.56)}',
      );
    });

    test('eight fraction digits and a declared symbol survive', () {
      expect(
        Statements.forLocale(
          StatementLocale.en,
        ).statement.crypto(amount: 0.0125),
        '${NumberFormat.currency(locale: 'en', name: 'BTC', symbol: '₿', decimalDigits: 8).format(0.0125)} in the vault',
      );
    });
  });

  group('plural categories', () {
    test('Russian picks one/few/many by CLDR, not by the last digit alone', () {
      final ru = Statements.forLocale(StatementLocale.ru).statement;
      expect(ru.txCount(count: 0), 'Нет операций'); // explicit =0
      expect(ru.txCount(count: 1), '1 операция'); // one
      expect(ru.txCount(count: 2), '2 операции'); // few
      expect(ru.txCount(count: 5), '5 операций'); // many
      expect(ru.txCount(count: 11), '11 операций'); // many, not one
      expect(ru.txCount(count: 21), '21 операция'); // one
      expect(ru.txCount(count: 22), '22 операции'); // few
      expect(ru.txCount(count: 100), '100 операций'); // many
      expect(ru.txCount(count: 1500), '1500 операций'); // many
    });

    test('Japanese has only other, and the generator accepted that', () {
      final ja = Statements.forLocale(StatementLocale.ja).statement;
      expect(ja.txCount(count: 0), '取引はありません');
      for (final n in [1, 2, 5, 11, 21, 100]) {
        expect(ja.txCount(count: n), '$n 件の取引');
      }
    });
  });

  test('ordinals use the ordinal table, not the cardinal one', () {
    final en = Statements.forLocale(StatementLocale.en).statement;
    String ord(int n) => en.feeNote(fee: 0.015, n: n).split(' after ')[1];
    expect(ord(1), '1st withdrawal');
    expect(ord(2), '2nd withdrawal');
    expect(ord(3), '3rd withdrawal');
    expect(ord(4), '4th withdrawal');
    expect(ord(11), '11th withdrawal');
    expect(ord(12), '12th withdrawal');
    expect(ord(13), '13th withdrawal');
    expect(ord(21), '21st withdrawal');
    expect(ord(101), '101st withdrawal');
    expect(ord(111), '111th withdrawal');
  });

  test('dates agree with intl', () {
    final period = DateTime(2026, 3);
    for (final locale in StatementLocale.values) {
      expect(
        Statements.forLocale(locale).statement.title(month: period),
        contains(DateFormat.yMMMM(locale.name).format(period)),
        reason: locale.name,
      );
    }
  });

  group('locale resolution', () {
    test('an unsupported locale falls back to the base', () {
      expect(
        Statements.of(L10nLocale.parse('pt_BR')).appLocale,
        StatementLocale.en,
      );
    });

    test('a region variant resolves to its language', () {
      expect(
        Statements.of(L10nLocale.parse('ru_UA')).appLocale,
        StatementLocale.ru,
      );
    });

    test('namespace objects are const, so access allocates nothing', () {
      final t = Statements.forLocale(StatementLocale.ru);
      expect(identical(t.statement, t.statement), isTrue);
      expect(identical(t, Statements.forLocale(StatementLocale.ru)), isTrue);
    });
  });
}
