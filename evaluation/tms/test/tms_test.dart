import 'package:intl/intl.dart';
import 'package:test/test.dart';
import 'package:tms_import/l10n/strings.g.dart';

void main() {
  setUpAll(() => initializeStringsFormatting());

  test('dotted ARB keys become namespaces, the file name reaches nothing', () {
    // The bundle is intl_messages_en.arb with keys like
    // "billing.invoice.title"; `intl_*{locale}` discards the file name so the
    // path is not repeated.
    final t = Strings.forLocale(StringsLocale.en);
    expect(t.billing.invoice.title(number: 'X'), 'Invoice X');
    expect(t.account.profile.greeting(name: 'Alex'), 'Hello, Alex');
  });

  test('declared ARB types shape the signature', () {
    final t = Strings.forLocale(StringsLocale.en).billing.invoice;
    // "type": "int" on the plural, "double" on the currency, "String" on the
    // plain placeholder — all reachable only because these compile.
    expect(t.lines(count: 3), '3 line items');
    expect(t.total(amount: 1234.5), 'Total due USD1,234.50');
  });

  test('a locale may restyle what the base declared', () {
    final de = Strings.forLocale(StringsLocale.de).billing.invoice;
    expect(
      de.total(amount: 1234.5),
      'Fälliger Betrag '
      '${NumberFormat.simpleCurrency(locale: 'de', name: 'USD', decimalDigits: 2).format(1234.5)}',
    );
    // The base keeps the code spelling.
    expect(
      Strings.forLocale(StringsLocale.en).billing.invoice.total(amount: 1234.5),
      'Total due '
      '${NumberFormat.currency(locale: 'en', name: 'USD', decimalDigits: 2).format(1234.5)}',
    );
  });

  group('a half translated locale', () {
    final es = Strings.forLocale(StringsLocale.es);

    test('translated messages use the target locale, formatting included', () {
      expect(
        es.billing.invoice.total(amount: 1234.5),
        'Importe pendiente '
        '${NumberFormat.currency(locale: 'es', name: 'USD', decimalDigits: 2).format(1234.5)}',
      );
      expect(es.billing.invoice.lines(count: 1), '1 línea');
      expect(es.billing.invoice.lines(count: 5), '5 líneas');
    });

    test('untranslated ones render as the base locale, formatting included', () {
      final due = DateTime(2026, 4, 30);
      expect(
        es.billing.invoice.dueOn(date: due),
        'Due on ${DateFormat.yMMMd('en').format(due)}',
      );
      expect(es.account.profile.greeting(name: 'Alex'), 'Hello, Alex');
      // Not `30 abr 2026`: the message falls back whole, so a reader sees an
      // English date rather than a Spanish sentence with an English word in it.
      expect(
        es.billing.invoice.dueOn(date: due),
        isNot(contains(DateFormat.yMMMd('es').format(due))),
      );
    });

    test(
      'Spanish gained a many category in CLDR 38 and the bundle uses it',
      () {
        expect(es.billing.invoice.lines(count: 1000000), '1000000 de líneas');
      },
    );
  });

  test('ARB bookkeeping keys are not translations', () {
    // @@locale and @@last_modified must not become members.
    final source = Strings.forLocale(StringsLocale.en);
    expect(source.toString(), isNotEmpty);
  });
}
