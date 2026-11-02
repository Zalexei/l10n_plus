@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/interfaces/app_localizations.g.dart';

/// Runs the `interfaces` golden instead of only reading it.
///
/// The thing the source cannot show: that one function takes both namespaces,
/// in either locale, and that it is the *static* type doing it — no map, no
/// string key, no `dynamic`. Everything below would be a compile error if the
/// generated types did not line up, which is most of the point.
void main() {
  final enT = AppLocalizations.forLocale(AppLocale.en);
  final ruT = AppLocalizations.forLocale(AppLocale.ru);

  /// The function the feature exists for: written once, against the type.
  String headline(ChangeData change) =>
      '${change.title}: ${change.rows.join(', ')}';

  /// And one over the other interface, to show the two are independent.
  String card(Plan plan) => '${plan.name} — ${plan.price} (${plan.cta})';

  /// Reached through the supertype's own member type, which is a supertype.
  String stamp(ChangeData change) => change.meta.date;

  /// Over the element type, which is the shape a pricing table wants.
  String rows(List<Feature> features) =>
      features.map((feature) => '${feature.title}: ${feature.note}').join('; ');

  group('one function over several namespaces', () {
    test('takes both children of the container', () {
      expect(headline(enT.onboarding.whatsNew.v2), 'New in 2.0: Add sync');
      expect(
        headline(enT.onboarding.whatsNew.v3),
        'New in 3.0: New game modes, And a lot more',
      );
    });

    test('and both namespaces of the explicit list', () {
      expect(card(enT.plans.free), 'Free — 0 a month (Start)');
      expect(card(enT.plans.pro), 'Pro — 9 a month (Upgrade)');
    });

    test('in any locale, because the type is not per locale', () {
      expect(
        headline(ruT.onboarding.whatsNew.v2),
        'Новое в 2.0: Синхронизация',
      );
      expect(card(ruT.plans.pro), 'Про — 9 в месяц (Перейти)');
    });

    test('a member that takes an argument is called through the type', () {
      ChangeData change = enT.onboarding.whatsNew.v3;
      expect(change.footer(year: '2026'), 'Shipped in 2026');
      change = ruT.onboarding.whatsNew.v3;
      expect(change.footer(year: '2026'), 'Вышло в 2026');
    });
  });

  group('a member that is a namespace', () {
    test('is read through the shared type', () {
      expect(stamp(enT.onboarding.whatsNew.v2), 'Shipped in May');
      expect(stamp(enT.onboarding.whatsNew.v3), 'Shipped in June');
      expect(stamp(ruT.onboarding.whatsNew.v2), 'Вышло в мае');
    });

    test('and the narrow type is still what the accessor gives', () {
      // Covariance: the same object, two static types, and the one the
      // namespace hands out is the specific one.
      expect(enT.onboarding.whatsNew.v2.meta, isA<ChangeMeta>());
      expect(enT.onboarding.whatsNew.v2.meta, isA<$OnboardingWhatsNewV2Meta>());
    });

    test('a list of the outer type reads the inner one', () {
      final changes = <ChangeData>[
        enT.onboarding.whatsNew.v2,
        enT.onboarding.whatsNew.v3,
      ];
      expect(changes.map(stamp), ['Shipped in May', 'Shipped in June']);
    });
  });

  group('an element type', () {
    test('one function over the elements of several collections', () {
      expect(rows(enT.plans.free.features), 'Sync: Once a day');
      expect(rows(enT.plans.pro.features), 'Sync: Live; Export: CSV and PDF');
      expect(rows(ruT.plans.free.features), 'Синхронизация: Раз в день');
    });

    test(
      'the narrow list goes in without a cast, because List is covariant',
      () {
        // No `.cast<Feature>()` anywhere above: the accessor hands out
        // `List<$PlansFreeFeaturesItem>` and that *is* a `List<Feature>`.
        expect(enT.plans.free.features, isA<List<Feature>>());
        expect(enT.plans.free.features, isA<List<$PlansFreeFeaturesItem>>());
      },
    );

    test('and through the namespace supertype as well', () {
      final blocks = <Plan>[enT.plans.free, enT.plans.pro];
      expect(blocks.map((plan) => plan.features.length), [1, 2]);
      expect(blocks.first.features.first.title, 'Sync');
    });

    test('the elements are still const, so reading one allocates nothing', () {
      expect(identical(enT.plans.pro.features, enT.plans.pro.features), isTrue);
    });
  });

  group('what the type is', () {
    test('a list of them is a list of one type', () {
      // Which is the shape an onboarding or a changelog screen actually
      // wants: iterate the versions and render each the same way.
      final changes = <ChangeData>[
        enT.onboarding.whatsNew.v2,
        enT.onboarding.whatsNew.v3,
      ];
      expect(changes.map((change) => change.rows.length), [1, 2]);
    });

    test('the namespaces own type is still there and still implemented', () {
      expect(enT.plans.free, isA<Plan>());
      expect(enT.plans.free, isA<$PlansFree>());
      // Two interfaces, one object: the supertype is added, nothing is
      // replaced.
      expect(enT.plans.pro, isA<Plan>());
    });

    test(
      'a const namespace is still const, so reading one allocates nothing',
      () {
        // `runtime_overrides` is off in this fixture, so the implementations are
        // `const` classes Dart canonicalizes: the same object every read.
        expect(identical(enT.plans.free, enT.plans.free), isTrue);
      },
    );
  });
}
