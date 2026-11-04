@TestOn('vm')
library;

import 'package:l10n_plus_generator/src/plural/cldr_plural_rules.dart';
import 'package:test/test.dart';

import 'cldr_plural_samples.dart';
import 'goldens/ordinals/app_localizations.g.dart' as ordinals;
import 'goldens/plurals/app_localizations.g.dart' as cardinals;

/// The rule tables, checked against the values CLDR publishes with them.
///
/// Every rule in `plurals.json` carries `@integer` and `@decimal` lists naming
/// values that must land in that category. They are the only authority on the
/// table that is not the table itself, and unlike `package:intl` — the other
/// oracle, in `plural_matrix_runtime_test.dart` — they come from the same
/// release the conditions were generated from.
///
/// What is executed here is the *generated code*, not the table: the golden
/// matrices are the conditions inlined into real Dart, so a mistake anywhere
/// between the CLDR text and the emitted `if` shows up.
void main() {
  test('every cardinal sample lands in the category CLDR lists it under', () {
    final mismatches = _check(
      samples: cldrCardinalSamples,
      table: CldrPluralRules.forLanguage,
      categoryOf: (language, value) => cardinals.AppLocalizations.forLocale(
        _cardinalLocale(language),
      ).cat(count: value),
      known: _cardinalLocales.keys.toSet(),
    );
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });

  test('every ordinal sample lands in the category CLDR lists it under', () {
    final mismatches = _check(
      samples: cldrOrdinalSamples,
      table: CldrPluralRules.ordinalForLanguage,
      categoryOf: (language, value) => ordinals.AppLocalizations.forLocale(
        _ordinalLocale(language),
      ).ord(count: value),
      known: _ordinalLocales.keys.toSet(),
    );
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });

  test('the samples cover every language in the tables', () {
    // A language whose every sample was dropped as unrepresentable would
    // silently stop being checked, so the coverage is asserted rather than
    // assumed.
    for (final language in CldrPluralRules.cardinalTags) {
      expect(
        cldrCardinalSamples[language],
        isNotNull,
        reason: '$language has no usable cardinal samples.',
      );
    }
    for (final language in CldrPluralRules.ordinalTags) {
      final rules = CldrPluralRules.ordinalForLanguage(language)!;
      if (rules.conditions.isEmpty) continue; // `other` only: nothing to check.
      expect(
        cldrOrdinalSamples[language],
        isNotNull,
        reason: '$language has no usable ordinal samples.',
      );
    }
  });

  test('the samples exercise every category each language declares', () {
    final gaps = <String>[];
    for (final language in CldrPluralRules.cardinalTags) {
      final declared = CldrPluralRules.forLanguage(
        language,
      )!.categories.map((category) => category.name);
      final covered = cldrCardinalSamples[language]?.keys.toSet() ?? {};
      for (final category in declared) {
        if (!covered.contains(category)) gaps.add('$language: $category');
      }
    }
    // `other` is the fallthrough and some languages illustrate it only with
    // values this runtime cannot be handed, so it is allowed to be missing.
    expect(
      gaps.where((gap) => !gap.endsWith(': other')),
      isEmpty,
      reason: gaps.join('\n'),
    );
  });
}

List<String> _check({
  required Map<String, Map<String, List<num>>> samples,
  required PluralRuleSet? Function(String) table,
  required String Function(String language, num value) categoryOf,
  required Set<String> known,
}) {
  final mismatches = <String>[];
  for (final entry in samples.entries) {
    final language = entry.key;
    if (table(language) == null || !known.contains(language)) continue;
    for (final categories in entry.value.entries) {
      for (final value in categories.value) {
        final ours = categoryOf(language, value);
        if (ours != categories.key) {
          mismatches.add(
            '$language($value): ours=$ours cldr=${categories.key}',
          );
        }
      }
    }
  }
  return mismatches;
}

/// The generated locale enums, keyed by CLDR tag, so a sample can be run
/// against the locale that carries its rules.
///
/// Keyed by the whole tag rather than the language: CLDR's samples for
/// `pt-PT` belong to the `pt_PT` locale, and keying by language would run
/// them against `pt` and call Brazilian answers correct.
final Map<String, cardinals.AppLocale> _cardinalLocales = {
  for (final locale in cardinals.AppLocale.values)
    locale.l10nLocale.toLanguageTag(): locale,
};

final Map<String, ordinals.AppLocale> _ordinalLocales = {
  for (final locale in ordinals.AppLocale.values)
    locale.l10nLocale.toLanguageTag(): locale,
};

cardinals.AppLocale _cardinalLocale(String language) =>
    _cardinalLocales[language]!;

ordinals.AppLocale _ordinalLocale(String language) =>
    _ordinalLocales[language]!;
