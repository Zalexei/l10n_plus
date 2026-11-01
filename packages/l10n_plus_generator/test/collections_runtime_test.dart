@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/collections/app_localizations.g.dart';

/// Runs the `collections` golden instead of only reading it.
///
/// Two things the source cannot show. That the accessors render the right
/// strings in the right order in each locale — a list is the one shape where
/// order *is* content — and that an override reaches one element without
/// disturbing its neighbours, which is the whole reason the elements are
/// members rather than literals when overrides are on.
void main() {
  const en = L10nLocale('en');

  final enT = AppLocalizations.forLocale(AppLocale.en);
  final ruT = AppLocalizations.forLocale(AppLocale.ru);

  tearDown(L10nOverrides.clear);

  group('a list', () {
    test('renders in order, per locale', () {
      expect(enT.onboarding.steps, [
        'Create an account',
        'Add a card',
        'You are done',
      ]);
      expect(ruT.onboarding.steps, [
        'Создайте аккаунт',
        'Добавьте карту',
        'Готово',
      ]);
    });

    test('is a list, so the count is content the translators own', () {
      // The point of having lists at all: adding a fourth onboarding step is
      // a change to a translation file, not to Dart.
      expect(enT.onboarding.steps.length, 3);
      expect(enT.onboarding.steps.first, 'Create an account');
      expect(enT.onboarding.steps.last, 'You are done');
    });
  });

  group('a map', () {
    test('renders per locale, keyed as the source wrote it', () {
      expect(enT.countries, {'fr': 'France', 'de': 'Germany', 'jp': 'Japan'});
      expect(ruT.countries['jp'], 'Япония');
      // The `(map)` suffix is a generation directive: it is in neither the
      // member name nor the keys.
      expect(enT.countries.keys, ['fr', 'de', 'jp']);
    });

    test('is a map, so it can be iterated and sorted', () {
      final names = enT.countries.values.toList()..sort();
      expect(names, ['France', 'Germany', 'Japan']);
    });
  });

  group('a list of records', () {
    test('every element has every field, in both locales', () {
      // The type says so and the build checked it; this is the same fact
      // executed, because a field that was missing would be a null here.
      for (final pages in [enT.onboarding.pages, ruT.onboarding.pages]) {
        expect(pages, hasLength(2));
        for (final page in pages) {
          expect(page.title, isNotEmpty);
          expect(page.body, isNotEmpty);
        }
      }
    });

    test('and renders in order, per locale', () {
      expect(enT.onboarding.pages[0].title, 'Create an account');
      expect(enT.onboarding.pages[1].body, 'We never store it');
      expect(ruT.onboarding.pages[0].title, 'Создайте аккаунт');
      expect(ruT.onboarding.pages[1].body, 'Мы её не храним');
    });

    test('a map of records is keyed by the map', () {
      expect(enT.plans['free']!.name, 'Free');
      expect(enT.plans['pro']!.note, 'Everything');
      expect(ruT.plans['pro']!.name, 'Про');
      expect(enT.plans.keys, ['free', 'pro']);
    });
  });

  group('with runtime overrides', () {
    test('a bundle replaces one element and leaves the rest', () {
      L10nOverrides.install(en, {'onboarding.steps.1': 'Add a payment method'});
      expect(enT.onboarding.steps, [
        'Create an account',
        'Add a payment method',
        'You are done',
      ]);
      // And only English moved.
      expect(ruT.onboarding.steps[1], 'Добавьте карту');
    });

    test('a map element too, named without the suffix', () {
      L10nOverrides.install(en, {'countries.de': 'Deutschland'});
      expect(enT.countries['de'], 'Deutschland');
      expect(enT.countries['fr'], 'France');
    });

    test('one field of one record, and nothing else', () {
      L10nOverrides.install(en, {'onboarding.pages.1.body': 'Stored nowhere'});
      expect(enT.onboarding.pages[1].body, 'Stored nowhere');
      expect(enT.onboarding.pages[1].title, 'Add a card');
      expect(enT.onboarding.pages[0].body, 'It takes a minute');
      expect(ruT.onboarding.pages[1].body, 'Мы её не храним');
    });

    test('and a field of a map record', () {
      L10nOverrides.install(en, {'plans.pro.note': 'Literally everything'});
      expect(enT.plans['pro']!.note, 'Literally everything');
      expect(enT.plans['free']!.note, 'One project');
    });

    test('and the collection is rebuilt, not cached', () {
      // The accessor is a getter over the members, so the next read sees the
      // install. A cached list would not.
      expect(enT.countries['fr'], 'France');
      L10nOverrides.install(en, {'countries.fr': 'La France'});
      expect(enT.countries['fr'], 'La France');
    });
  });
}
