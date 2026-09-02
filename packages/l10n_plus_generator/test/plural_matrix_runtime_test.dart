@TestOn('vm')
library;

import 'package:intl/intl.dart';
import 'package:l10n_plus_generator/src/plural/cldr_plural_rules.dart';
import 'package:test/test.dart';

import 'goldens/plurals/app_localizations.g.dart';

/// The curated CLDR table, checked against a second implementation of the
/// same data.
///
/// The table in `cldr_plural_rules.dart` is written by hand, and a wrong
/// condition is exactly the failure this library exists to prevent — it
/// compiles, it analyzes, it renders a plausible sentence, and it is wrong in
/// one language nobody on the team reads. `package:intl` carries its own copy
/// of the CLDR rules, generated from ICU data, so it is an independent
/// oracle. This executes the generated matrix and compares every branch
/// against it.
///
/// Ordinals have no counterpart in `intl` and stay hand-verified.
void main() {
  /// The category `intl` picks, with its explicit `=0/=1/=2` shortcut off so
  /// that what comes back is the CLDR category and nothing else.
  String intlCategory(String language, num n) => Intl.pluralLogic<String>(
    n,
    zero: 'zero',
    one: 'one',
    two: 'two',
    few: 'few',
    many: 'many',
    other: 'other',
    locale: language,
    useExplicitNumberCases: false,
  );

  /// Integers, teens, round tens, the 100..103 boundary Arabic turns on, the
  /// whole millions the Romance languages turn on, and fractions, which carry
  /// the operands `v` and `t` that naive implementations drop.
  ///
  /// Fractions ending in `.5` are deliberately absent: `intl` computes the
  /// operand `i` as `n.round()` where CLDR defines it as the integer digits
  /// of `n`, so `intl` reads 1.5 as i = 2. That is a defect in the oracle,
  /// not in the table, and those values are asserted by hand below instead of
  /// being compared against it.
  final samples = <num>[
    ...List<int>.generate(31, (i) => i),
    ...[40, 50, 55, 60, 80, 90, 99, 100, 101, 102, 103, 110, 111, 112],
    ...[113, 114, 115, 120, 121, 122, 200, 201, 202, 1000, 1001, 1002],
    ...[1011, 1012, 1013, 10000, 999999, 1000000, 1000001, 2000000],
    ...[0.0, 1.0, 2.0, 3.0, 0.1, 0.2, 1.1, 1.2, 2.1, 3.1, 10.1, 11.1],
    ...[100.1, 103.1, 1000.1, 0.01, 1.01, 1.10],
  ];

  test('every sample lands in the same category as package:intl', () {
    final mismatches = <String>[];
    for (final locale in AppLocale.values) {
      final language = locale.l10nLocale.language;
      final t = AppLocalizations.forLocale(locale);
      for (final sample in samples) {
        final ours = t.cat(count: sample);
        final theirs = intlCategory(language, sample);
        if (ours != theirs) {
          mismatches.add('$language($sample): ours=$ours intl=$theirs');
        }
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });

  test(
    'a language never produces a category its rule set does not declare',
    () {
      for (final locale in AppLocale.values) {
        final language = locale.l10nLocale.language;
        final declared = CldrPluralRules.forLanguage(
          language,
        )!.categories.map((c) => c.name).toSet();
        final t = AppLocalizations.forLocale(locale);
        for (final sample in samples) {
          expect(
            declared,
            contains(t.cat(count: sample)),
            reason: '$language($sample)',
          );
        }
      }
    },
  );

  test('no language is missing a category CLDR gives it', () {
    // The direction that catches an omission rather than a wrong condition:
    // es, fr, it and pt were missing `many` until the oracle said so.
    final missing = <String>[];
    for (final locale in AppLocale.values) {
      final language = locale.l10nLocale.language;
      final declared = CldrPluralRules.forLanguage(
        language,
      )!.categories.map((c) => c.name).toSet();
      final reachable = {
        for (final sample in samples) intlCategory(language, sample),
      };
      final gap = reachable.difference(declared);
      if (gap.isNotEmpty) missing.add('$language: ${gap.join(', ')}');
    }
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('the oracle is a real second opinion, not a copy of ours', () {
    // If `intl` silently answered `other` for everything the first test
    // would pass for the wrong reason.
    expect(intlCategory('ru', 1), 'one');
    expect(intlCategory('ru', 2), 'few');
    expect(intlCategory('ru', 5), 'many');
    expect(intlCategory('ar', 0), 'zero');
    expect(intlCategory('ar', 2), 'two');
    expect(intlCategory('ar', 103), 'few');
    expect(intlCategory('ja', 5), 'other');
  });

  test('CLDR ranges match integers only, which is where intl is right', () {
    // UTS #35: a range never matches a non-integer. Arabic is where that is
    // visible: 3 is `few`, 3.5 is `other`.
    final ar = AppLocalizations.forLocale(AppLocale.ar);
    expect(ar.cat(count: 3), 'few');
    expect(ar.cat(count: 3.5), 'other');
    expect(ar.cat(count: 3.1), 'other');
    expect(ar.cat(count: 11), 'many');
    expect(ar.cat(count: 11.1), 'other');
    expect(ar.cat(count: 103), 'few');
  });

  test('half fractions, where the oracle itself is wrong', () {
    // `intl` reads i as n.round(), so it answers `other` for all of these.
    // CLDR takes i as the integer digits, which is what the table encodes;
    // the values below are CLDR's own published samples.
    expect(AppLocalizations.forLocale(AppLocale.fr).cat(count: 1.5), 'one');
    expect(AppLocalizations.forLocale(AppLocale.pt).cat(count: 1.5), 'one');
    expect(AppLocalizations.forLocale(AppLocale.da).cat(count: 1.5), 'one');
    expect(AppLocalizations.forLocale(AppLocale.hi).cat(count: 0.5), 'one');
    expect(AppLocalizations.forLocale(AppLocale.he).cat(count: 0.5), 'one');
    expect(AppLocalizations.forLocale(AppLocale.ar).cat(count: 3.5), 'other');
  });

  test('the Romance millions category', () {
    // CLDR 38 gave es, fr, it and pt a `many` for whole millions, which is
    // what makes "1 million de livres" possible.
    for (final locale in [
      AppLocale.es,
      AppLocale.fr,
      AppLocale.it,
      AppLocale.pt,
    ]) {
      final t = AppLocalizations.forLocale(locale);
      expect(t.cat(count: 1000000), 'many', reason: locale.name);
      expect(t.cat(count: 2000000), 'many', reason: locale.name);
      expect(t.cat(count: 1000001), isNot('many'), reason: locale.name);
      expect(t.cat(count: 0), isNot('many'), reason: locale.name);
    }
  });

  test('Romanian few starts the range at 1, so 101 is few', () {
    final ro = AppLocalizations.forLocale(AppLocale.ro);
    expect(ro.cat(count: 1), 'one');
    expect(ro.cat(count: 0), 'few');
    expect(ro.cat(count: 19), 'few');
    expect(ro.cat(count: 20), 'other');
    expect(ro.cat(count: 101), 'few');
    expect(ro.cat(count: 1001), 'few');
    expect(ro.cat(count: 121), 'other');
  });
}
