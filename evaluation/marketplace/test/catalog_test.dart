// Plural correctness for four languages with four different plural systems.
// The expected values are CLDR's, written out by hand and cross-checked
// against package:intl's own rule table in
// packages/l10n_plus_generator/test/cldr_vs_intl_test.dart.
import 'package:marketplace/l10n/catalog.g.dart';
import 'package:intl/intl.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => initializeCatalogFormatting());

  group('Arabic uses all six categories', () {
    late final t = Catalog.forLocale(CatalogLocale.ar).search;

    test('zero, one and two are distinct forms', () {
      expect(t.reviews(count: 0), 'لا مراجعات');
      expect(t.reviews(count: 1), 'مراجعة واحدة');
      expect(t.reviews(count: 2), 'مراجعتان');
    });

    test('few is n % 100 in 3..10, and wraps at 103', () {
      for (final n in [3, 7, 10, 103, 110, 1003]) {
        expect(t.reviews(count: n), endsWith('مراجعات'), reason: '$n');
      }
    });

    test('many is n % 100 in 11..99', () {
      for (final n in [11, 26, 99, 111, 199]) {
        expect(t.reviews(count: n), endsWith('مراجعة'), reason: '$n');
        expect(t.reviews(count: n), isNot(endsWith('مراجعات')), reason: '$n');
      }
    });

    test('100, 101, 102 and 1.5 fall through to other', () {
      for (final n in <num>[100, 101, 102, 1.5, 0.5]) {
        expect(t.reviews(count: n), endsWith('مراجعة'), reason: '$n');
      }
    });
  });

  group('Polish few/many is not "ends in 2,3,4"', () {
    late final t = Catalog.forLocale(CatalogLocale.pl).search;
    String form(num n) => t.reviews(count: n).split(' ').last;

    test('one only for exactly 1', () {
      expect(form(1), 'opinia');
      expect(form(21), isNot('opinia'));
      expect(form(101), isNot('opinia'));
    });

    test('few for x2..x4 except the teens', () {
      for (final n in [2, 3, 4, 22, 102, 1002]) {
        expect(form(n), 'opinie', reason: '$n');
      }
      for (final n in [12, 13, 14]) {
        expect(form(n), 'opinii', reason: 'teen $n must be many');
      }
    });

    test('many for 0, 5..9, teens and round tens', () {
      for (final n in [0, 5, 9, 11, 15, 20, 21, 100, 1500]) {
        // 0 hits the explicit =0 branch, so compare on the plural forms only.
        if (n == 0) continue;
        expect(form(n), 'opinii', reason: '$n');
      }
    });

    test('a fraction is other, never one/few/many', () {
      expect(t.reviews(count: 1.5), '1,5 opinii');
      expect(t.reviews(count: 2.5), '2,5 opinii');
    });
  });

  group('Japanese has no plural categories at all', () {
    late final t = Catalog.forLocale(CatalogLocale.ja).search;

    test('every count above the explicit =0 renders the same shape', () {
      for (final n in [1, 2, 3, 5, 11, 21, 100, 1000]) {
        expect(
          t.reviews(count: n),
          'レビュー ${NumberFormat.decimalPattern('ja').format(n)}件',
        );
      }
      expect(t.reviews(count: 0), 'レビューなし');
    });
  });

  group('English', () {
    late final t = Catalog.forLocale(CatalogLocale.en).search;

    test('one only for the integer 1', () {
      expect(t.reviews(count: 1), '1 review');
      expect(t.reviews(count: 1.0), '1 review'); // v == 0
      expect(t.reviews(count: 1.5), '1.5 reviews');
    });
  });

  group('offset: follows ICU', () {
    test('=N matches the original value, # sees the adjusted one', () {
      final en = Catalog.forLocale(CatalogLocale.en).order;
      expect(en.items(count: 0, first: 'A'), 'Nothing');
      expect(en.items(count: 1, first: 'A'), 'Just A');
      expect(en.items(count: 2, first: 'A'), 'A and 1 other');
      expect(en.items(count: 5, first: 'A'), 'A and 4 others');
      final pl = Catalog.forLocale(CatalogLocale.pl).order;
      // 5 - 1 = 4 -> few in Polish, not many.
      expect(pl.items(count: 5, first: 'A'), 'A i 4 inne');
      // 6 - 1 = 5 -> many.
      expect(pl.items(count: 6, first: 'A'), 'A i 5 innych');
    });
  });

  group('selectordinal selects on the ordinal table', () {
    test('English ordinals, including the teens', () {
      final en = Catalog.forLocale(CatalogLocale.en).order;
      expect(en.rank(n: 1), 'Your 1st order');
      expect(en.rank(n: 2), 'Your 2nd order');
      expect(en.rank(n: 3), 'Your 3rd order');
      expect(en.rank(n: 4), 'Your 4th order');
      expect(en.rank(n: 11), 'Your 11th order');
      expect(en.rank(n: 12), 'Your 12th order');
      expect(en.rank(n: 13), 'Your 13th order');
      expect(en.rank(n: 21), 'Your 21st order');
      expect(en.rank(n: 111), 'Your 111th order');
      // The cardinal table would say `other` for everything but 1.
      expect(
        Catalog.forLocale(CatalogLocale.en).search.reviews(count: 2),
        '2 reviews',
      );
    });

    test('a language whose ordinals have one form says so once', () {
      // Slovenian has four cardinal categories and one ordinal one; this
      // message could not be generated at all before the ordinal table grew.
      final sl = Catalog.forLocale(CatalogLocale.sl).order;
      for (final n in [1, 2, 3, 4, 11, 21, 101]) {
        expect(sl.rank(n: n), 'Vaše $n. naročilo');
      }
      // …while its cardinals still distinguish four forms.
      final search = Catalog.forLocale(CatalogLocale.sl).search;
      expect(search.reviews(count: 1), '1 mnenje');
      expect(search.reviews(count: 2), '2 mnenji');
    });

    test('Arabic, Japanese and Polish ordinals are one form each', () {
      for (final locale in [
        CatalogLocale.ar,
        CatalogLocale.ja,
        CatalogLocale.pl,
      ]) {
        final t = Catalog.forLocale(locale).order;
        expect(
          t.rank(n: 1),
          t.rank(n: 3).replaceAll('3', '1'),
          reason: locale.name,
        );
      }
    });
  });

  group('format_plural_numbers: true routes # through NumberFormat', () {
    test('grouping follows the locale', () {
      expect(
        Catalog.forLocale(CatalogLocale.en).search.reviews(count: 1500),
        '1,500 reviews',
      );
      expect(
        Catalog.forLocale(CatalogLocale.pl).search.reviews(count: 1500),
        '${NumberFormat.decimalPattern('pl').format(1500)} opinii',
      );
    });
  });

  group('compact numbers are the locale\'s, not a suffix table', () {
    test('agrees with intl computed directly', () {
      for (final locale in CatalogLocale.values) {
        final tag = locale.name;
        expect(
          Catalog.forLocale(locale).search.viewers(count: 12345),
          contains(NumberFormat.compact(locale: tag).format(12345)),
          reason: tag,
        );
        expect(
          Catalog.forLocale(locale).search.sold(count: 2400000),
          contains(NumberFormat.compactLong(locale: tag).format(2400000)),
          reason: tag,
        );
      }
    });

    test('Japanese compacts on 万, English on K', () {
      expect(
        Catalog.forLocale(CatalogLocale.ja).search.viewers(count: 12345),
        startsWith('1.23万'),
      );
      expect(
        Catalog.forLocale(CatalogLocale.en).search.viewers(count: 12345),
        startsWith('12.3K'),
      );
    });
  });

  group('Slovenian has a dual, which naive implementations lose', () {
    late final t = Catalog.forLocale(CatalogLocale.sl).search;
    String form(num n) => t.results(count: n, query: 'q').split(' ')[1];

    test('one/two/few key off i % 100, so 101 is one and 102 is two', () {
      expect(form(1), 'zadetek');
      expect(form(2), 'zadetka');
      expect(form(3), 'zadetki');
      expect(form(4), 'zadetki');
      expect(form(5), 'zadetkov');
      expect(form(101), 'zadetek');
      expect(form(102), 'zadetka');
      expect(form(103), 'zadetki');
      expect(form(105), 'zadetkov');
    });

    test('a fraction is few in Slovenian, not other', () {
      expect(form(1.5), 'zadetki');
    });
  });

  test('select branches are enums, so a typo cannot reach run time', () {
    final t = Catalog.forLocale(CatalogLocale.en).cart;
    expect(
      t.shipping(kind: CartShippingKind.pickup, days: 0),
      'Pick up in store: today',
    );
    expect(
      t.shipping(kind: CartShippingKind.standard, days: 3),
      'Standard delivery: 3 days',
    );
  });
}
