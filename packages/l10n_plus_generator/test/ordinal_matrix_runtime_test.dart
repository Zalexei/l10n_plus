@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/src/ast/message_ast.dart';
import 'package:l10n_plus_generator/src/plural/cldr_plural_rules.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'goldens/ordinals/app_localizations.g.dart';

/// The curated CLDR **ordinal** table, checked against ICU.
///
/// `package:intl` ships cardinal rules only, so the oracle that
/// `plural_matrix_runtime_test.dart` uses does not exist for
/// `selectordinal`. ICU has one, reachable through
/// `Intl.PluralRules(locale, {type: 'ordinal'})`, and its answers are
/// vendored in `test/data/cldr_ordinals.json` so this suite needs nothing but
/// Dart. `tool/ordinal_oracle.sh` regenerates that file; the header of the
/// file records which ICU and CLDR produced it.
///
/// Ordinals matter more than their rarity suggests: a wrong one is invisible
/// to everyone who does not read the language, and "21th" is the kind of
/// thing a native speaker notices immediately and a test suite never does.
void main() {
  final packageRoot = p.dirname(
    p.dirname(
      Isolate.resolvePackageUriSync(
        Uri.parse('package:l10n_plus_generator/l10n_plus_generator.dart'),
      )!.toFilePath(),
    ),
  );

  final oracle =
      jsonDecode(
            File(
              p.join(packageRoot, 'test/data/cldr_ordinals.json'),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  final legend = (oracle['legend'] as Map<String, dynamic>).map(
    (code, name) => MapEntry(code, name as String),
  );
  final samples = (oracle['samples'] as List<dynamic>).cast<num>();
  final locales = oracle['locales'] as Map<String, dynamic>;

  String icuCategory(String language, int index) =>
      legend[(locales[language]! as String)[index]]!;

  final aliased = (oracle['aliased'] as Map<String, dynamic>).map(
    (code, target) => MapEntry(code, target as String),
  );

  test('the vendored oracle accounts for every language in the table', () {
    // Every ordinal language is either checked against ICU or recorded as one
    // ICU folds onto another name — `mo` onto `ro`, `sh` onto `sr`. Those
    // rules are still CLDR's own; what is missing is a second opinion on a
    // name ICU does not keep, and saying so beats quietly not covering them.
    expect(
      {...locales.keys, ...aliased.keys},
      CldrPluralRules.supportedOrdinalLanguages.toSet(),
      reason:
          'Run tool/ordinal_oracle.sh after changing the language list, so '
          'the check does not quietly stop covering something.',
    );
    expect(
      locales.length,
      greaterThan(100),
      reason: 'Only ${locales.length} languages are actually checked.',
    );
  });

  test('every sample lands in the category ICU picks', () {
    final mismatches = <String>[];
    for (final locale in AppLocale.values) {
      final language = locale.l10nLocale.toLanguageTag();
      if (!locales.containsKey(language)) continue; // ICU folds it away.
      final t = AppLocalizations.forLocale(locale);
      for (var i = 0; i < samples.length; i++) {
        final ours = t.ord(count: samples[i]);
        final theirs = icuCategory(language, i);
        if (ours != theirs) {
          mismatches.add('$language(${samples[i]}): ours=$ours icu=$theirs');
        }
      }
    }
    expect(
      mismatches.length,
      0,
      reason:
          '${mismatches.length} mismatch(es):\n'
          '${mismatches.take(40).join('\n')}',
    );
  });

  test(
    'a language never produces a category its rule set does not declare',
    () {
      for (final locale in AppLocale.values) {
        final language = locale.l10nLocale.toLanguageTag();
        final declared = CldrPluralRules.ordinalForLanguage(
          language,
        )!.categories.map((c) => c.name).toSet();
        final t = AppLocalizations.forLocale(locale);
        for (final sample in samples) {
          expect(
            declared,
            contains(t.ord(count: sample)),
            reason: '$language($sample)',
          );
        }
      }
    },
  );

  test('the oracle is a real second opinion, not a copy of ours', () {
    // If the vendored file were all `other` the first test would pass for
    // the wrong reason. These are the ordinals a reader of the language
    // would notice.
    int at(num value) => samples.indexOf(value);
    expect(icuCategory('en', at(1)), 'one');
    expect(icuCategory('en', at(11)), 'other');
    expect(icuCategory('en', at(21)), 'one');
    expect(icuCategory('mk', at(7)), 'many');
    expect(icuCategory('az', at(100)), 'few');
    expect(icuCategory('az', at(1000)), 'other');
    expect(icuCategory('it', at(800)), 'many');
    expect(icuCategory('sl', at(3)), 'other');
  });

  group('the ordinal table is not the cardinal one', () {
    test('English: one/two/few for ordinals, one/other for cardinals', () {
      final en = AppLocalizations.forLocale(AppLocale.en);
      expect(en.ord(count: 1), 'one'); // 1st
      expect(en.ord(count: 2), 'two'); // 2nd
      expect(en.ord(count: 3), 'few'); // 3rd
      expect(en.ord(count: 4), 'other'); // 4th
      expect(en.ord(count: 11), 'other'); // 11th, not 11st
      expect(en.ord(count: 21), 'one'); // 21st
      expect(CldrPluralRules.forLanguage('en')!.categories.length, 2);
    });

    test('Slovenian: four cardinal categories, one ordinal', () {
      expect(CldrPluralRules.forLanguage('sl')!.categories.length, 4);
      expect(CldrPluralRules.ordinalForLanguage('sl')!.categories, {
        PluralCategory.other,
      });
    });
  });

  group('n and i are not interchangeable', () {
    test('English reads n, so a fraction is other', () {
      // The rule is `n % 10 = 1`; 1.5 % 10 is 1.5, which is not 1.
      final en = AppLocalizations.forLocale(AppLocale.en);
      expect(en.ord(count: 1.5), 'other');
      expect(en.ord(count: 1.0), 'one');
    });

    test('Azerbaijani reads i, so a fraction follows its integer part', () {
      final az = AppLocalizations.forLocale(AppLocale.az);
      expect(az.ord(count: 1.5), 'one');
      expect(az.ord(count: 0.5), 'many');
    });

    test('Nepali reads a range, which matches integers only', () {
      final ne = AppLocalizations.forLocale(AppLocale.ne);
      expect(ne.ord(count: 2), 'one');
      expect(ne.ord(count: 2.5), 'other');
    });
  });
}
