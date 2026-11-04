import 'package:l10n_plus/l10n_plus.dart';

import '../ast/message_ast.dart';

/// Cardinal plural rules for one language.
///
/// Conditions are Dart source fragments in which `@` is a placeholder for the
/// name of the [PluralOperands] variable the generator emits. Keeping them as
/// source means the runtime ships no rule table at all: the generator inlines
/// the condition for the one locale it is generating.
final class PluralRuleSet {
  /// Creates a rule set.
  const PluralRuleSet(this.conditions);

  /// Condition per category, in evaluation order. Never contains
  /// [PluralCategory.other], which is the fallthrough.
  final Map<PluralCategory, String> conditions;

  /// Categories this language can actually produce, `other` included.
  Set<PluralCategory> get categories => {
    ...conditions.keys,
    PluralCategory.other,
  };

  /// The single value [category] matches, when it matches exactly one.
  ///
  /// English `one` is `i = 1 and v = 0`, which is true of 1 and of nothing
  /// else, so an explicit `=1` branch renders every value the category could
  /// ever select and the category is not missing. Russian `one` also takes 21
  /// and 31, so no single `=N` closes it and this returns null.
  ///
  /// Read off the generated condition rather than listed by hand: a hand
  /// written list would drift from the conditions, and the condition is the
  /// thing that actually runs.
  int? exactValueOf(PluralCategory category) {
    final condition = conditions[category];
    if (condition == null) return null;
    final match = _singleValue.firstMatch(condition);
    if (match == null) return null;
    return int.parse(match.group(1) ?? match.group(2)!);
  }

  /// The two shapes CLDR uses for a category of exactly one value.
  static final RegExp _singleValue = RegExp(
    r'^@n == (\d+)$|^@i == (\d+) && @v == 0$',
  );
}

/// The CLDR plural rules, whole.
///
/// Generated from CLDR 48 by
/// `tool/update_cldr_plural_rules.dart`. Every language CLDR
/// publishes is here, so adding a locale to a project never
/// stops at the table; a language CLDR does not know still
/// gets a diagnostic rather than English rules.
///
/// Two CLDR subtleties are compiled in rather than left to the
/// reader:
///
/// * a range matches **integers only** (UTS #35), so
///   `n % 100 = 3..10` is `few` for 3 and `other` for 3.5.
///   `@n == @i` is what says "n is an integer" in operands;
/// * the operand `e`, the exponent of a compact form, is
///   always 0 here because nothing formats compactly before
///   selecting a branch. Relations over it are decided at
///   generation time and do not reach the output.
///
///
/// Most entries are keyed by language. The few CLDR qualifies
/// by script or region are here too, because one of them is
/// not its language: `pt-PT` counts `one` for 1 alone where
/// `pt` counts it for 0 and 1 both. [cardinalFor] and
/// [ordinalFor] walk a locale lineage to find them.
abstract final class CldrPluralRules {
  /// The CLDR release these tables were generated from.
  static const String cldrVersion = '48';

  /// Cardinal rules keyed by language subtag.
  static const Map<String, PluralRuleSet> _rules = {
    'af': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ak': PluralRuleSet({
      // n = 0..1
      PluralCategory.one: '@n == @i && @n >= 0 && @n <= 1',
    }),
    'am': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'an': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ar': PluralRuleSet({
      // n = 0
      PluralCategory.zero: '@n == 0',
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
      // n % 100 = 3..10
      PluralCategory.few: '@n == @i && @n % 100 >= 3 && @n % 100 <= 10',
      // n % 100 = 11..99
      PluralCategory.many: '@n == @i && @n % 100 >= 11 && @n % 100 <= 99',
    }),
    'ars': PluralRuleSet({
      // n = 0
      PluralCategory.zero: '@n == 0',
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
      // n % 100 = 3..10
      PluralCategory.few: '@n == @i && @n % 100 >= 3 && @n % 100 <= 10',
      // n % 100 = 11..99
      PluralCategory.many: '@n == @i && @n % 100 >= 11 && @n % 100 <= 99',
    }),
    'as': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'asa': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ast': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'az': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'bal': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'be': PluralRuleSet({
      // n % 10 = 1 and n % 100 != 11
      PluralCategory.one: '@n % 10 == 1 && @n % 100 != 11',
      // n % 10 = 2..4 and n % 100 != 12..14
      PluralCategory.few:
          '@n == @i && @n % 10 >= 2 && @n % 10 <= 4 && !(@n == @i && @n % 100 >= 12 && @n % 100 <= 14)',
      // n % 10 = 0 or n % 10 = 5..9 or n % 100 = 11..14
      PluralCategory.many:
          '@n % 10 == 0 || @n == @i && @n % 10 >= 5 && @n % 10 <= 9 || @n == @i && @n % 100 >= 11 && @n % 100 <= 14',
    }),
    'bem': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'bez': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'bg': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'bho': PluralRuleSet({
      // n = 0..1
      PluralCategory.one: '@n == @i && @n >= 0 && @n <= 1',
    }),
    'blo': PluralRuleSet({
      // n = 0
      PluralCategory.zero: '@n == 0',
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'bm': PluralRuleSet({}),
    'bn': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'bo': PluralRuleSet({}),
    'br': PluralRuleSet({
      // n % 10 = 1 and n % 100 != 11,71,91
      PluralCategory.one:
          '@n % 10 == 1 && @n % 100 != 11 && @n % 100 != 71 && @n % 100 != 91',
      // n % 10 = 2 and n % 100 != 12,72,92
      PluralCategory.two:
          '@n % 10 == 2 && @n % 100 != 12 && @n % 100 != 72 && @n % 100 != 92',
      // n % 10 = 3..4,9 and n % 100 != 10..19,70..79,90..99
      PluralCategory.few:
          '(@n == @i && @n % 10 >= 3 && @n % 10 <= 4 || @n % 10 == 9) && !(@n == @i && @n % 100 >= 10 && @n % 100 <= 19 || @n == @i && @n % 100 >= 70 && @n % 100 <= 79 || @n == @i && @n % 100 >= 90 && @n % 100 <= 99)',
      // n != 0 and n % 1000000 = 0
      PluralCategory.many: '@n != 0 && @n % 1000000 == 0',
    }),
    'brx': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'bs': PluralRuleSet({
      // v = 0 and i % 10 = 1 and i % 100 != 11 or f % 10 = 1 and f % 100 != 11
      PluralCategory.one:
          '@v == 0 && @i % 10 == 1 && @i % 100 != 11 || @f % 10 == 1 && @f % 100 != 11',
      // v = 0 and i % 10 = 2..4 and i % 100 != 12..14 or f % 10 = 2..4 and f % 100 != 12..14
      PluralCategory.few:
          '@v == 0 && @i % 10 >= 2 && @i % 10 <= 4 && !(@i % 100 >= 12 && @i % 100 <= 14) || @f % 10 >= 2 && @f % 10 <= 4 && !(@f % 100 >= 12 && @f % 100 <= 14)',
    }),
    'ca': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5
      PluralCategory.many: '@i != 0 && @i % 1000000 == 0 && @v == 0',
    }),
    'ce': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ceb': PluralRuleSet({
      // v = 0 and i = 1,2,3 or v = 0 and i % 10 != 4,6,9 or v != 0 and f % 10 != 4,6,9
      PluralCategory.one:
          '@v == 0 && (@i == 1 || @i == 2 || @i == 3) || @v == 0 && @i % 10 != 4 && @i % 10 != 6 && @i % 10 != 9 || @v != 0 && @f % 10 != 4 && @f % 10 != 6 && @f % 10 != 9',
    }),
    'cgg': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'chr': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ckb': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'cs': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // i = 2..4 and v = 0
      PluralCategory.few: '@i >= 2 && @i <= 4 && @v == 0',
      // v != 0
      PluralCategory.many: '@v != 0',
    }),
    'csw': PluralRuleSet({
      // n = 0..1
      PluralCategory.one: '@n == @i && @n >= 0 && @n <= 1',
    }),
    'cv': PluralRuleSet({
      // n = 0
      PluralCategory.zero: '@n == 0',
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'cy': PluralRuleSet({
      // n = 0
      PluralCategory.zero: '@n == 0',
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
      // n = 3
      PluralCategory.few: '@n == 3',
      // n = 6
      PluralCategory.many: '@n == 6',
    }),
    'da': PluralRuleSet({
      // n = 1 or t != 0 and i = 0,1
      PluralCategory.one: '@n == 1 || @t != 0 && (@i == 0 || @i == 1)',
    }),
    'de': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'doi': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'dsb': PluralRuleSet({
      // v = 0 and i % 100 = 1 or f % 100 = 1
      PluralCategory.one: '@v == 0 && @i % 100 == 1 || @f % 100 == 1',
      // v = 0 and i % 100 = 2 or f % 100 = 2
      PluralCategory.two: '@v == 0 && @i % 100 == 2 || @f % 100 == 2',
      // v = 0 and i % 100 = 3..4 or f % 100 = 3..4
      PluralCategory.few:
          '@v == 0 && @i % 100 >= 3 && @i % 100 <= 4 || @f % 100 >= 3 && @f % 100 <= 4',
    }),
    'dv': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'dz': PluralRuleSet({}),
    'ee': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'el': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'en': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'eo': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'es': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5
      PluralCategory.many: '@i != 0 && @i % 1000000 == 0 && @v == 0',
    }),
    'et': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'eu': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'fa': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'ff': PluralRuleSet({
      // i = 0,1
      PluralCategory.one: '(@i == 0 || @i == 1)',
    }),
    'fi': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'fil': PluralRuleSet({
      // v = 0 and i = 1,2,3 or v = 0 and i % 10 != 4,6,9 or v != 0 and f % 10 != 4,6,9
      PluralCategory.one:
          '@v == 0 && (@i == 1 || @i == 2 || @i == 3) || @v == 0 && @i % 10 != 4 && @i % 10 != 6 && @i % 10 != 9 || @v != 0 && @f % 10 != 4 && @f % 10 != 6 && @f % 10 != 9',
    }),
    'fo': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'fr': PluralRuleSet({
      // i = 0,1
      PluralCategory.one: '(@i == 0 || @i == 1)',
      // e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5
      PluralCategory.many: '@i != 0 && @i % 1000000 == 0 && @v == 0',
    }),
    'fur': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'fy': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'ga': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
      // n = 3..6
      PluralCategory.few: '@n == @i && @n >= 3 && @n <= 6',
      // n = 7..10
      PluralCategory.many: '@n == @i && @n >= 7 && @n <= 10',
    }),
    'gd': PluralRuleSet({
      // n = 1,11
      PluralCategory.one: '(@n == 1 || @n == 11)',
      // n = 2,12
      PluralCategory.two: '(@n == 2 || @n == 12)',
      // n = 3..10,13..19
      PluralCategory.few:
          '(@n == @i && @n >= 3 && @n <= 10 || @n == @i && @n >= 13 && @n <= 19)',
    }),
    'gl': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'gsw': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'gu': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'guw': PluralRuleSet({
      // n = 0..1
      PluralCategory.one: '@n == @i && @n >= 0 && @n <= 1',
    }),
    'gv': PluralRuleSet({
      // v = 0 and i % 10 = 1
      PluralCategory.one: '@v == 0 && @i % 10 == 1',
      // v = 0 and i % 10 = 2
      PluralCategory.two: '@v == 0 && @i % 10 == 2',
      // v = 0 and i % 100 = 0,20,40,60,80
      PluralCategory.few:
          '@v == 0 && (@i % 100 == 0 || @i % 100 == 20 || @i % 100 == 40 || @i % 100 == 60 || @i % 100 == 80)',
      // v != 0
      PluralCategory.many: '@v != 0',
    }),
    'ha': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'haw': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'he': PluralRuleSet({
      // i = 1 and v = 0 or i = 0 and v != 0
      PluralCategory.one: '@i == 1 && @v == 0 || @i == 0 && @v != 0',
      // i = 2 and v = 0
      PluralCategory.two: '@i == 2 && @v == 0',
    }),
    'hi': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'hnj': PluralRuleSet({}),
    'hr': PluralRuleSet({
      // v = 0 and i % 10 = 1 and i % 100 != 11 or f % 10 = 1 and f % 100 != 11
      PluralCategory.one:
          '@v == 0 && @i % 10 == 1 && @i % 100 != 11 || @f % 10 == 1 && @f % 100 != 11',
      // v = 0 and i % 10 = 2..4 and i % 100 != 12..14 or f % 10 = 2..4 and f % 100 != 12..14
      PluralCategory.few:
          '@v == 0 && @i % 10 >= 2 && @i % 10 <= 4 && !(@i % 100 >= 12 && @i % 100 <= 14) || @f % 10 >= 2 && @f % 10 <= 4 && !(@f % 100 >= 12 && @f % 100 <= 14)',
    }),
    'hsb': PluralRuleSet({
      // v = 0 and i % 100 = 1 or f % 100 = 1
      PluralCategory.one: '@v == 0 && @i % 100 == 1 || @f % 100 == 1',
      // v = 0 and i % 100 = 2 or f % 100 = 2
      PluralCategory.two: '@v == 0 && @i % 100 == 2 || @f % 100 == 2',
      // v = 0 and i % 100 = 3..4 or f % 100 = 3..4
      PluralCategory.few:
          '@v == 0 && @i % 100 >= 3 && @i % 100 <= 4 || @f % 100 >= 3 && @f % 100 <= 4',
    }),
    'hu': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'hy': PluralRuleSet({
      // i = 0,1
      PluralCategory.one: '(@i == 0 || @i == 1)',
    }),
    'ia': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'id': PluralRuleSet({}),
    'ie': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'ig': PluralRuleSet({}),
    'ii': PluralRuleSet({}),
    'io': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'is': PluralRuleSet({
      // t = 0 and i % 10 = 1 and i % 100 != 11 or t % 10 = 1 and t % 100 != 11
      PluralCategory.one:
          '@t == 0 && @i % 10 == 1 && @i % 100 != 11 || @t % 10 == 1 && @t % 100 != 11',
    }),
    'it': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5
      PluralCategory.many: '@i != 0 && @i % 1000000 == 0 && @v == 0',
    }),
    'iu': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
    }),
    'ja': PluralRuleSet({}),
    'jbo': PluralRuleSet({}),
    'jgo': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'jmc': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'jv': PluralRuleSet({}),
    'jw': PluralRuleSet({}),
    'ka': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'kab': PluralRuleSet({
      // i = 0,1
      PluralCategory.one: '(@i == 0 || @i == 1)',
    }),
    'kaj': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'kcg': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'kde': PluralRuleSet({}),
    'kea': PluralRuleSet({}),
    'kk': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'kkj': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'kl': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'km': PluralRuleSet({}),
    'kn': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'ko': PluralRuleSet({}),
    'kok': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'kok-Latn': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'ks': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ksb': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ksh': PluralRuleSet({
      // n = 0
      PluralCategory.zero: '@n == 0',
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ku': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'kw': PluralRuleSet({
      // n = 0
      PluralCategory.zero: '@n == 0',
      // n = 1
      PluralCategory.one: '@n == 1',
      // n % 100 = 2,22,42,62,82 or n % 1000 = 0 and n % 100000 = 1000..20000,40000,60000,80000 or n != 0 and n % 1000000 = 100000
      PluralCategory.two:
          '(@n % 100 == 2 || @n % 100 == 22 || @n % 100 == 42 || @n % 100 == 62 || @n % 100 == 82) || @n % 1000 == 0 && (@n == @i && @n % 100000 >= 1000 && @n % 100000 <= 20000 || @n % 100000 == 40000 || @n % 100000 == 60000 || @n % 100000 == 80000) || @n != 0 && @n % 1000000 == 100000',
      // n % 100 = 3,23,43,63,83
      PluralCategory.few:
          '(@n % 100 == 3 || @n % 100 == 23 || @n % 100 == 43 || @n % 100 == 63 || @n % 100 == 83)',
      // n != 1 and n % 100 = 1,21,41,61,81
      PluralCategory.many:
          '@n != 1 && (@n % 100 == 1 || @n % 100 == 21 || @n % 100 == 41 || @n % 100 == 61 || @n % 100 == 81)',
    }),
    'ky': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'lag': PluralRuleSet({
      // n = 0
      PluralCategory.zero: '@n == 0',
      // i = 0,1 and n != 0
      PluralCategory.one: '(@i == 0 || @i == 1) && @n != 0',
    }),
    'lb': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'lg': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'lij': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'lkt': PluralRuleSet({}),
    'lld': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5
      PluralCategory.many: '@i != 0 && @i % 1000000 == 0 && @v == 0',
    }),
    'ln': PluralRuleSet({
      // n = 0..1
      PluralCategory.one: '@n == @i && @n >= 0 && @n <= 1',
    }),
    'lo': PluralRuleSet({}),
    'lt': PluralRuleSet({
      // n % 10 = 1 and n % 100 != 11..19
      PluralCategory.one:
          '@n % 10 == 1 && !(@n == @i && @n % 100 >= 11 && @n % 100 <= 19)',
      // n % 10 = 2..9 and n % 100 != 11..19
      PluralCategory.few:
          '@n == @i && @n % 10 >= 2 && @n % 10 <= 9 && !(@n == @i && @n % 100 >= 11 && @n % 100 <= 19)',
      // f != 0
      PluralCategory.many: '@f != 0',
    }),
    'lv': PluralRuleSet({
      // n % 10 = 0 or n % 100 = 11..19 or v = 2 and f % 100 = 11..19
      PluralCategory.zero:
          '@n % 10 == 0 || @n == @i && @n % 100 >= 11 && @n % 100 <= 19 || @v == 2 && @f % 100 >= 11 && @f % 100 <= 19',
      // n % 10 = 1 and n % 100 != 11 or v = 2 and f % 10 = 1 and f % 100 != 11 or v != 2 and f % 10 = 1
      PluralCategory.one:
          '@n % 10 == 1 && @n % 100 != 11 || @v == 2 && @f % 10 == 1 && @f % 100 != 11 || @v != 2 && @f % 10 == 1',
    }),
    'mas': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'mg': PluralRuleSet({
      // n = 0..1
      PluralCategory.one: '@n == @i && @n >= 0 && @n <= 1',
    }),
    'mgo': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'mk': PluralRuleSet({
      // v = 0 and i % 10 = 1 and i % 100 != 11 or f % 10 = 1 and f % 100 != 11
      PluralCategory.one:
          '@v == 0 && @i % 10 == 1 && @i % 100 != 11 || @f % 10 == 1 && @f % 100 != 11',
    }),
    'ml': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'mn': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'mo': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // v != 0 or n = 0 or n != 1 and n % 100 = 1..19
      PluralCategory.few:
          '@v != 0 || @n == 0 || @n != 1 && @n == @i && @n % 100 >= 1 && @n % 100 <= 19',
    }),
    'mr': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ms': PluralRuleSet({}),
    'mt': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
      // n = 0 or n % 100 = 3..10
      PluralCategory.few:
          '@n == 0 || @n == @i && @n % 100 >= 3 && @n % 100 <= 10',
      // n % 100 = 11..19
      PluralCategory.many: '@n == @i && @n % 100 >= 11 && @n % 100 <= 19',
    }),
    'my': PluralRuleSet({}),
    'nah': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'naq': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
    }),
    'nb': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'nd': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ne': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'nl': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'nn': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'nnh': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'no': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'nqo': PluralRuleSet({}),
    'nr': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'nso': PluralRuleSet({
      // n = 0..1
      PluralCategory.one: '@n == @i && @n >= 0 && @n <= 1',
    }),
    'ny': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'nyn': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'om': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'or': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'os': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'osa': PluralRuleSet({}),
    'pa': PluralRuleSet({
      // n = 0..1
      PluralCategory.one: '@n == @i && @n >= 0 && @n <= 1',
    }),
    'pap': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'pcm': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
    'pl': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // v = 0 and i % 10 = 2..4 and i % 100 != 12..14
      PluralCategory.few:
          '@v == 0 && @i % 10 >= 2 && @i % 10 <= 4 && !(@i % 100 >= 12 && @i % 100 <= 14)',
      // v = 0 and i != 1 and i % 10 = 0..1 or v = 0 and i % 10 = 5..9 or v = 0 and i % 100 = 12..14
      PluralCategory.many:
          '@v == 0 && @i != 1 && @i % 10 >= 0 && @i % 10 <= 1 || @v == 0 && @i % 10 >= 5 && @i % 10 <= 9 || @v == 0 && @i % 100 >= 12 && @i % 100 <= 14',
    }),
    'prg': PluralRuleSet({
      // n % 10 = 0 or n % 100 = 11..19 or v = 2 and f % 100 = 11..19
      PluralCategory.zero:
          '@n % 10 == 0 || @n == @i && @n % 100 >= 11 && @n % 100 <= 19 || @v == 2 && @f % 100 >= 11 && @f % 100 <= 19',
      // n % 10 = 1 and n % 100 != 11 or v = 2 and f % 10 = 1 and f % 100 != 11 or v != 2 and f % 10 = 1
      PluralCategory.one:
          '@n % 10 == 1 && @n % 100 != 11 || @v == 2 && @f % 10 == 1 && @f % 100 != 11 || @v != 2 && @f % 10 == 1',
    }),
    'ps': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'pt': PluralRuleSet({
      // i = 0..1
      PluralCategory.one: '@i >= 0 && @i <= 1',
      // e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5
      PluralCategory.many: '@i != 0 && @i % 1000000 == 0 && @v == 0',
    }),
    'pt-PT': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5
      PluralCategory.many: '@i != 0 && @i % 1000000 == 0 && @v == 0',
    }),
    'rm': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ro': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // v != 0 or n = 0 or n != 1 and n % 100 = 1..19
      PluralCategory.few:
          '@v != 0 || @n == 0 || @n != 1 && @n == @i && @n % 100 >= 1 && @n % 100 <= 19',
    }),
    'rof': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ru': PluralRuleSet({
      // v = 0 and i % 10 = 1 and i % 100 != 11
      PluralCategory.one: '@v == 0 && @i % 10 == 1 && @i % 100 != 11',
      // v = 0 and i % 10 = 2..4 and i % 100 != 12..14
      PluralCategory.few:
          '@v == 0 && @i % 10 >= 2 && @i % 10 <= 4 && !(@i % 100 >= 12 && @i % 100 <= 14)',
      // v = 0 and i % 10 = 0 or v = 0 and i % 10 = 5..9 or v = 0 and i % 100 = 11..14
      PluralCategory.many:
          '@v == 0 && @i % 10 == 0 || @v == 0 && @i % 10 >= 5 && @i % 10 <= 9 || @v == 0 && @i % 100 >= 11 && @i % 100 <= 14',
    }),
    'rwk': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'sah': PluralRuleSet({}),
    'saq': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'sat': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
    }),
    'sc': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'scn': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5
      PluralCategory.many: '@i != 0 && @i % 1000000 == 0 && @v == 0',
    }),
    'sd': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'sdh': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'se': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
    }),
    'seh': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ses': PluralRuleSet({}),
    'sg': PluralRuleSet({}),
    'sgs': PluralRuleSet({
      // n % 10 = 1 and n % 100 != 11
      PluralCategory.one: '@n % 10 == 1 && @n % 100 != 11',
      // n = 2
      PluralCategory.two: '@n == 2',
      // n != 2 and n % 10 = 2..9 and n % 100 != 11..19
      PluralCategory.few:
          '@n != 2 && @n == @i && @n % 10 >= 2 && @n % 10 <= 9 && !(@n == @i && @n % 100 >= 11 && @n % 100 <= 19)',
      // f != 0
      PluralCategory.many: '@f != 0',
    }),
    'sh': PluralRuleSet({
      // v = 0 and i % 10 = 1 and i % 100 != 11 or f % 10 = 1 and f % 100 != 11
      PluralCategory.one:
          '@v == 0 && @i % 10 == 1 && @i % 100 != 11 || @f % 10 == 1 && @f % 100 != 11',
      // v = 0 and i % 10 = 2..4 and i % 100 != 12..14 or f % 10 = 2..4 and f % 100 != 12..14
      PluralCategory.few:
          '@v == 0 && @i % 10 >= 2 && @i % 10 <= 4 && !(@i % 100 >= 12 && @i % 100 <= 14) || @f % 10 >= 2 && @f % 10 <= 4 && !(@f % 100 >= 12 && @f % 100 <= 14)',
    }),
    'shi': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
      // n = 2..10
      PluralCategory.few: '@n == @i && @n >= 2 && @n <= 10',
    }),
    'si': PluralRuleSet({
      // n = 0,1 or i = 0 and f = 1
      PluralCategory.one: '(@n == 0 || @n == 1) || @i == 0 && @f == 1',
    }),
    'sk': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // i = 2..4 and v = 0
      PluralCategory.few: '@i >= 2 && @i <= 4 && @v == 0',
      // v != 0
      PluralCategory.many: '@v != 0',
    }),
    'sl': PluralRuleSet({
      // v = 0 and i % 100 = 1
      PluralCategory.one: '@v == 0 && @i % 100 == 1',
      // v = 0 and i % 100 = 2
      PluralCategory.two: '@v == 0 && @i % 100 == 2',
      // v = 0 and i % 100 = 3..4 or v != 0
      PluralCategory.few:
          '@v == 0 && @i % 100 >= 3 && @i % 100 <= 4 || @v != 0',
    }),
    'sma': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
    }),
    'smi': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
    }),
    'smj': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
    }),
    'smn': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
    }),
    'sms': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
    }),
    'sn': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'so': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'sq': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'sr': PluralRuleSet({
      // v = 0 and i % 10 = 1 and i % 100 != 11 or f % 10 = 1 and f % 100 != 11
      PluralCategory.one:
          '@v == 0 && @i % 10 == 1 && @i % 100 != 11 || @f % 10 == 1 && @f % 100 != 11',
      // v = 0 and i % 10 = 2..4 and i % 100 != 12..14 or f % 10 = 2..4 and f % 100 != 12..14
      PluralCategory.few:
          '@v == 0 && @i % 10 >= 2 && @i % 10 <= 4 && !(@i % 100 >= 12 && @i % 100 <= 14) || @f % 10 >= 2 && @f % 10 <= 4 && !(@f % 100 >= 12 && @f % 100 <= 14)',
    }),
    'ss': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ssy': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'st': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'su': PluralRuleSet({}),
    'sv': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'sw': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'syr': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ta': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'te': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'teo': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'th': PluralRuleSet({}),
    'ti': PluralRuleSet({
      // n = 0..1
      PluralCategory.one: '@n == @i && @n >= 0 && @n <= 1',
    }),
    'tig': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'tk': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'tl': PluralRuleSet({
      // v = 0 and i = 1,2,3 or v = 0 and i % 10 != 4,6,9 or v != 0 and f % 10 != 4,6,9
      PluralCategory.one:
          '@v == 0 && (@i == 1 || @i == 2 || @i == 3) || @v == 0 && @i % 10 != 4 && @i % 10 != 6 && @i % 10 != 9 || @v != 0 && @f % 10 != 4 && @f % 10 != 6 && @f % 10 != 9',
    }),
    'tn': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'to': PluralRuleSet({}),
    'tpi': PluralRuleSet({}),
    'tr': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ts': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'tzm': PluralRuleSet({
      // n = 0..1 or n = 11..99
      PluralCategory.one:
          '@n == @i && @n >= 0 && @n <= 1 || @n == @i && @n >= 11 && @n <= 99',
    }),
    'ug': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'uk': PluralRuleSet({
      // v = 0 and i % 10 = 1 and i % 100 != 11
      PluralCategory.one: '@v == 0 && @i % 10 == 1 && @i % 100 != 11',
      // v = 0 and i % 10 = 2..4 and i % 100 != 12..14
      PluralCategory.few:
          '@v == 0 && @i % 10 >= 2 && @i % 10 <= 4 && !(@i % 100 >= 12 && @i % 100 <= 14)',
      // v = 0 and i % 10 = 0 or v = 0 and i % 10 = 5..9 or v = 0 and i % 100 = 11..14
      PluralCategory.many:
          '@v == 0 && @i % 10 == 0 || @v == 0 && @i % 10 >= 5 && @i % 10 <= 9 || @v == 0 && @i % 100 >= 11 && @i % 100 <= 14',
    }),
    'und': PluralRuleSet({}),
    'ur': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'uz': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    've': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'vec': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
      // e = 0 and i != 0 and i % 1000000 = 0 and v = 0 or e != 0..5
      PluralCategory.many: '@i != 0 && @i % 1000000 == 0 && @v == 0',
    }),
    'vi': PluralRuleSet({}),
    'vo': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'vun': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'wa': PluralRuleSet({
      // n = 0..1
      PluralCategory.one: '@n == @i && @n >= 0 && @n <= 1',
    }),
    'wae': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'wo': PluralRuleSet({}),
    'xh': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'xog': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'yi': PluralRuleSet({
      // i = 1 and v = 0
      PluralCategory.one: '@i == 1 && @v == 0',
    }),
    'yo': PluralRuleSet({}),
    'yue': PluralRuleSet({}),
    'zh': PluralRuleSet({}),
    'zu': PluralRuleSet({
      // i = 0 or n = 1
      PluralCategory.one: '@i == 0 || @n == 1',
    }),
  };

  /// Ordinal rules, used by `selectordinal`.
  ///
  /// A different CLDR table from the cardinal one: English is
  /// `one/two/few/other` for ordinals but only `one/other` for
  /// cardinals. Far fewer languages have ordinal rules, and a
  /// language missing here produces `unknown_ordinal_language`
  /// rather than silently borrowing English behaviour.
  static const Map<String, PluralRuleSet> _ordinalRules = {
    'af': PluralRuleSet({}),
    'am': PluralRuleSet({}),
    'an': PluralRuleSet({}),
    'ar': PluralRuleSet({}),
    'as': PluralRuleSet({
      // n = 1,5,7,8,9,10
      PluralCategory.one:
          '(@n == 1 || @n == 5 || @n == 7 || @n == 8 || @n == 9 || @n == 10)',
      // n = 2,3
      PluralCategory.two: '(@n == 2 || @n == 3)',
      // n = 4
      PluralCategory.few: '@n == 4',
      // n = 6
      PluralCategory.many: '@n == 6',
    }),
    'ast': PluralRuleSet({}),
    'az': PluralRuleSet({
      // i % 10 = 1,2,5,7,8 or i % 100 = 20,50,70,80
      PluralCategory.one:
          '(@i % 10 == 1 || @i % 10 == 2 || @i % 10 == 5 || @i % 10 == 7 || @i % 10 == 8) || (@i % 100 == 20 || @i % 100 == 50 || @i % 100 == 70 || @i % 100 == 80)',
      // i % 10 = 3,4 or i % 1000 = 100,200,300,400,500,600,700,800,900
      PluralCategory.few:
          '(@i % 10 == 3 || @i % 10 == 4) || (@i % 1000 == 100 || @i % 1000 == 200 || @i % 1000 == 300 || @i % 1000 == 400 || @i % 1000 == 500 || @i % 1000 == 600 || @i % 1000 == 700 || @i % 1000 == 800 || @i % 1000 == 900)',
      // i = 0 or i % 10 = 6 or i % 100 = 40,60,90
      PluralCategory.many:
          '@i == 0 || @i % 10 == 6 || (@i % 100 == 40 || @i % 100 == 60 || @i % 100 == 90)',
    }),
    'bal': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'be': PluralRuleSet({
      // n % 10 = 2,3 and n % 100 != 12,13
      PluralCategory.few:
          '(@n % 10 == 2 || @n % 10 == 3) && @n % 100 != 12 && @n % 100 != 13',
    }),
    'bg': PluralRuleSet({}),
    'blo': PluralRuleSet({
      // i = 0
      PluralCategory.zero: '@i == 0',
      // i = 1
      PluralCategory.one: '@i == 1',
      // i = 2,3,4,5,6
      PluralCategory.few:
          '(@i == 2 || @i == 3 || @i == 4 || @i == 5 || @i == 6)',
    }),
    'bn': PluralRuleSet({
      // n = 1,5,7,8,9,10
      PluralCategory.one:
          '(@n == 1 || @n == 5 || @n == 7 || @n == 8 || @n == 9 || @n == 10)',
      // n = 2,3
      PluralCategory.two: '(@n == 2 || @n == 3)',
      // n = 4
      PluralCategory.few: '@n == 4',
      // n = 6
      PluralCategory.many: '@n == 6',
    }),
    'bs': PluralRuleSet({}),
    'ca': PluralRuleSet({
      // n = 1,3
      PluralCategory.one: '(@n == 1 || @n == 3)',
      // n = 2
      PluralCategory.two: '@n == 2',
      // n = 4
      PluralCategory.few: '@n == 4',
    }),
    'ce': PluralRuleSet({}),
    'cs': PluralRuleSet({}),
    'cv': PluralRuleSet({}),
    'cy': PluralRuleSet({
      // n = 0,7,8,9
      PluralCategory.zero: '(@n == 0 || @n == 7 || @n == 8 || @n == 9)',
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2
      PluralCategory.two: '@n == 2',
      // n = 3,4
      PluralCategory.few: '(@n == 3 || @n == 4)',
      // n = 5,6
      PluralCategory.many: '(@n == 5 || @n == 6)',
    }),
    'da': PluralRuleSet({}),
    'de': PluralRuleSet({}),
    'dsb': PluralRuleSet({}),
    'el': PluralRuleSet({}),
    'en': PluralRuleSet({
      // n % 10 = 1 and n % 100 != 11
      PluralCategory.one: '@n % 10 == 1 && @n % 100 != 11',
      // n % 10 = 2 and n % 100 != 12
      PluralCategory.two: '@n % 10 == 2 && @n % 100 != 12',
      // n % 10 = 3 and n % 100 != 13
      PluralCategory.few: '@n % 10 == 3 && @n % 100 != 13',
    }),
    'es': PluralRuleSet({}),
    'et': PluralRuleSet({}),
    'eu': PluralRuleSet({}),
    'fa': PluralRuleSet({}),
    'fi': PluralRuleSet({}),
    'fil': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'fr': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'fy': PluralRuleSet({}),
    'ga': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'gd': PluralRuleSet({
      // n = 1,11
      PluralCategory.one: '(@n == 1 || @n == 11)',
      // n = 2,12
      PluralCategory.two: '(@n == 2 || @n == 12)',
      // n = 3,13
      PluralCategory.few: '(@n == 3 || @n == 13)',
    }),
    'gl': PluralRuleSet({}),
    'gsw': PluralRuleSet({}),
    'gu': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2,3
      PluralCategory.two: '(@n == 2 || @n == 3)',
      // n = 4
      PluralCategory.few: '@n == 4',
      // n = 6
      PluralCategory.many: '@n == 6',
    }),
    'he': PluralRuleSet({}),
    'hi': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2,3
      PluralCategory.two: '(@n == 2 || @n == 3)',
      // n = 4
      PluralCategory.few: '@n == 4',
      // n = 6
      PluralCategory.many: '@n == 6',
    }),
    'hr': PluralRuleSet({}),
    'hsb': PluralRuleSet({}),
    'hu': PluralRuleSet({
      // n = 1,5
      PluralCategory.one: '(@n == 1 || @n == 5)',
    }),
    'hy': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ia': PluralRuleSet({}),
    'id': PluralRuleSet({}),
    'ie': PluralRuleSet({}),
    'is': PluralRuleSet({}),
    'it': PluralRuleSet({
      // n = 11,8,80,800
      PluralCategory.many: '(@n == 11 || @n == 8 || @n == 80 || @n == 800)',
    }),
    'ja': PluralRuleSet({}),
    'ka': PluralRuleSet({
      // i = 1
      PluralCategory.one: '@i == 1',
      // i = 0 or i % 100 = 2..20,40,60,80
      PluralCategory.many:
          '@i == 0 || (@i % 100 >= 2 && @i % 100 <= 20 || @i % 100 == 40 || @i % 100 == 60 || @i % 100 == 80)',
    }),
    'kk': PluralRuleSet({
      // n % 10 = 6 or n % 10 = 9 or n % 10 = 0 and n != 0
      PluralCategory.many:
          '@n % 10 == 6 || @n % 10 == 9 || @n % 10 == 0 && @n != 0',
    }),
    'km': PluralRuleSet({}),
    'kn': PluralRuleSet({}),
    'ko': PluralRuleSet({}),
    'kok': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2,3
      PluralCategory.two: '(@n == 2 || @n == 3)',
      // n = 4
      PluralCategory.few: '@n == 4',
    }),
    'kok-Latn': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2,3
      PluralCategory.two: '(@n == 2 || @n == 3)',
      // n = 4
      PluralCategory.few: '@n == 4',
    }),
    'kw': PluralRuleSet({
      // n = 1..4 or n % 100 = 1..4,21..24,41..44,61..64,81..84
      PluralCategory.one:
          '@n == @i && @n >= 1 && @n <= 4 || (@n == @i && @n % 100 >= 1 && @n % 100 <= 4 || @n == @i && @n % 100 >= 21 && @n % 100 <= 24 || @n == @i && @n % 100 >= 41 && @n % 100 <= 44 || @n == @i && @n % 100 >= 61 && @n % 100 <= 64 || @n == @i && @n % 100 >= 81 && @n % 100 <= 84)',
      // n = 5 or n % 100 = 5
      PluralCategory.many: '@n == 5 || @n % 100 == 5',
    }),
    'ky': PluralRuleSet({}),
    'lij': PluralRuleSet({
      // n = 11,8,80..89,800..899
      PluralCategory.many:
          '(@n == 11 || @n == 8 || @n == @i && @n >= 80 && @n <= 89 || @n == @i && @n >= 800 && @n <= 899)',
    }),
    'lld': PluralRuleSet({
      // n = 11,8,80,800
      PluralCategory.many: '(@n == 11 || @n == 8 || @n == 80 || @n == 800)',
    }),
    'lo': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'lt': PluralRuleSet({}),
    'lv': PluralRuleSet({}),
    'mk': PluralRuleSet({
      // i % 10 = 1 and i % 100 != 11
      PluralCategory.one: '@i % 10 == 1 && @i % 100 != 11',
      // i % 10 = 2 and i % 100 != 12
      PluralCategory.two: '@i % 10 == 2 && @i % 100 != 12',
      // i % 10 = 7,8 and i % 100 != 17,18
      PluralCategory.many:
          '(@i % 10 == 7 || @i % 10 == 8) && @i % 100 != 17 && @i % 100 != 18',
    }),
    'ml': PluralRuleSet({}),
    'mn': PluralRuleSet({}),
    'mo': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'mr': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n = 2,3
      PluralCategory.two: '(@n == 2 || @n == 3)',
      // n = 4
      PluralCategory.few: '@n == 4',
    }),
    'ms': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'my': PluralRuleSet({}),
    'nb': PluralRuleSet({}),
    'ne': PluralRuleSet({
      // n = 1..4
      PluralCategory.one: '@n == @i && @n >= 1 && @n <= 4',
    }),
    'nl': PluralRuleSet({}),
    'no': PluralRuleSet({}),
    'or': PluralRuleSet({
      // n = 1,5,7..9
      PluralCategory.one:
          '(@n == 1 || @n == 5 || @n == @i && @n >= 7 && @n <= 9)',
      // n = 2,3
      PluralCategory.two: '(@n == 2 || @n == 3)',
      // n = 4
      PluralCategory.few: '@n == 4',
      // n = 6
      PluralCategory.many: '@n == 6',
    }),
    'pa': PluralRuleSet({}),
    'pl': PluralRuleSet({}),
    'prg': PluralRuleSet({}),
    'ps': PluralRuleSet({}),
    'pt': PluralRuleSet({}),
    'ro': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'ru': PluralRuleSet({}),
    'sc': PluralRuleSet({
      // n = 11,8,80,800
      PluralCategory.many: '(@n == 11 || @n == 8 || @n == 80 || @n == 800)',
    }),
    'scn': PluralRuleSet({
      // n = 11,8,80..89,800..899
      PluralCategory.many:
          '(@n == 11 || @n == 8 || @n == @i && @n >= 80 && @n <= 89 || @n == @i && @n >= 800 && @n <= 899)',
    }),
    'sd': PluralRuleSet({}),
    'sh': PluralRuleSet({}),
    'si': PluralRuleSet({}),
    'sk': PluralRuleSet({}),
    'sl': PluralRuleSet({}),
    'sq': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
      // n % 10 = 4 and n % 100 != 14
      PluralCategory.many: '@n % 10 == 4 && @n % 100 != 14',
    }),
    'sr': PluralRuleSet({}),
    'sv': PluralRuleSet({
      // n % 10 = 1,2 and n % 100 != 11,12
      PluralCategory.one:
          '(@n % 10 == 1 || @n % 10 == 2) && @n % 100 != 11 && @n % 100 != 12',
    }),
    'sw': PluralRuleSet({}),
    'ta': PluralRuleSet({}),
    'te': PluralRuleSet({}),
    'th': PluralRuleSet({}),
    'tk': PluralRuleSet({
      // n % 10 = 6,9 or n = 10
      PluralCategory.few: '(@n % 10 == 6 || @n % 10 == 9) || @n == 10',
    }),
    'tl': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'tpi': PluralRuleSet({}),
    'tr': PluralRuleSet({}),
    'uk': PluralRuleSet({
      // n % 10 = 3 and n % 100 != 13
      PluralCategory.few: '@n % 10 == 3 && @n % 100 != 13',
    }),
    'und': PluralRuleSet({}),
    'ur': PluralRuleSet({}),
    'uz': PluralRuleSet({}),
    'vec': PluralRuleSet({
      // n = 11,8,80,800
      PluralCategory.many: '(@n == 11 || @n == 8 || @n == 80 || @n == 800)',
    }),
    'vi': PluralRuleSet({
      // n = 1
      PluralCategory.one: '@n == 1',
    }),
    'yue': PluralRuleSet({}),
    'zh': PluralRuleSet({}),
    'zu': PluralRuleSet({}),
  };

  /// The cardinal rules CLDR gives [locale], and the tag they came from.
  ///
  /// CLDR keys most of its rules by language and a few by script or region,
  /// and one of those is not its language: `pt-PT` counts `one` for 1 alone
  /// where `pt` counts it for 0 and 1 both. So this walks
  /// [L10nLocale.lineage], most specific first, which is how ICU reaches the
  /// same entry.
  ///
  /// CLDR's `parentLocales` are not read, so a region with no entry of its
  /// own takes its language: `pt-MZ` inherits `pt-PT` in ICU and `pt` here.
  static ({String tag, PluralRuleSet rules})? cardinalFor(L10nLocale locale) =>
      _lookup(_rules, locale);

  /// The ordinal rules CLDR gives [locale], resolved as in [cardinalFor].
  static ({String tag, PluralRuleSet rules})? ordinalFor(L10nLocale locale) =>
      _lookup(_ordinalRules, locale);

  static ({String tag, PluralRuleSet rules})? _lookup(
    Map<String, PluralRuleSet> table,
    L10nLocale locale,
  ) {
    for (final candidate in locale.lineage) {
      final tag = candidate.toLanguageTag();
      final rules = table[tag];
      if (rules != null) return (tag: tag, rules: rules);
    }
    return null;
  }

  /// Cardinal rules published under exactly [tag], or `null`.
  ///
  /// Takes a CLDR table key rather than a locale: for asking whether a
  /// language is in the table at all, where no fallback is wanted.
  static PluralRuleSet? forLanguage(String tag) => _rules[tag];

  /// Ordinal rules published under exactly [tag], or `null`.
  static PluralRuleSet? ordinalForLanguage(String tag) => _ordinalRules[tag];

  /// Every language with cardinal rules, sorted, for diagnostics.
  ///
  /// Language subtags only. The qualified tags in the table are not
  /// languages, and a diagnostic that counts languages must not count them.
  static List<String> get supportedLanguages => _languagesOf(_rules);

  /// Every language with ordinal rules, sorted, for diagnostics.
  static List<String> get supportedOrdinalLanguages =>
      _languagesOf(_ordinalRules);

  /// Every key of the cardinal table, qualified tags included, sorted.
  ///
  /// For tests that have to cover the table itself rather than report on
  /// languages, where leaving `pt-PT` out would leave it unchecked.
  static List<String> get cardinalTags => _tagsOf(_rules);

  /// Every key of the ordinal table, qualified tags included, sorted.
  static List<String> get ordinalTags => _tagsOf(_ordinalRules);

  static List<String> _languagesOf(Map<String, PluralRuleSet> table) =>
      table.keys.where((tag) => !tag.contains('-')).toList(growable: false)
        ..sort();

  static List<String> _tagsOf(Map<String, PluralRuleSet> table) =>
      table.keys.toList(growable: false)..sort();
}
