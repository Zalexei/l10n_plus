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
}

/// The CLDR cardinal rules the generator knows about.
///
/// Deliberately a curated table rather than a generated dump: an unknown
/// language produces a clear diagnostic instead of silently falling back to
/// English rules, which is the classic way localization libraries ship wrong
/// plurals.
abstract final class CldrPluralRules {
  /// Rules keyed by lowercase language subtag.
  static const Map<String, PluralRuleSet> _rules = {
    // one: i = 1 and v = 0
    'en': PluralRuleSet({PluralCategory.one: '@i == 1 && @v == 0'}),
    'de': PluralRuleSet({PluralCategory.one: '@i == 1 && @v == 0'}),
    'nl': PluralRuleSet({PluralCategory.one: '@i == 1 && @v == 0'}),
    'sv': PluralRuleSet({PluralCategory.one: '@i == 1 && @v == 0'}),
    'et': PluralRuleSet({PluralCategory.one: '@i == 1 && @v == 0'}),
    'fi': PluralRuleSet({PluralCategory.one: '@i == 1 && @v == 0'}),
    'it': PluralRuleSet({
      PluralCategory.one: '@i == 1 && @v == 0',
      PluralCategory.many: _millions,
    }),
    'el': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'es': PluralRuleSet({
      PluralCategory.one: '@n == 1',
      PluralCategory.many: _millions,
    }),
    'tr': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'az': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'nb': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'no': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    // one: n = 1 or t != 0 and i = 0,1
    'da': PluralRuleSet({
      PluralCategory.one: '@n == 1 || @t != 0 && (@i == 0 || @i == 1)',
    }),
    // one: i = 0,1
    'fr': PluralRuleSet({
      PluralCategory.one: '@i == 0 || @i == 1',
      PluralCategory.many: _millions,
    }),
    // one: i = 0..1
    'pt': PluralRuleSet({
      PluralCategory.one: '@i >= 0 && @i <= 1',
      PluralCategory.many: _millions,
    }),
    // one: i = 0 or n = 1
    'hi': PluralRuleSet({PluralCategory.one: '@i == 0 || @n == 1'}),
    'ru': _slavic,
    'uk': _slavic,
    'pl': PluralRuleSet({
      PluralCategory.one: '@i == 1 && @v == 0',
      PluralCategory.few:
          '@v == 0 && @i % 10 >= 2 && @i % 10 <= 4 && '
          '!(@i % 100 >= 12 && @i % 100 <= 14)',
      PluralCategory.many:
          '@v == 0 && @i != 1 && @i % 10 >= 0 && @i % 10 <= 1 || '
          '@v == 0 && @i % 10 >= 5 && @i % 10 <= 9 || '
          '@v == 0 && @i % 100 >= 12 && @i % 100 <= 14',
    }),
    'cs': _westSlavic,
    'sk': _westSlavic,
    'sr': _bcs,
    'hr': _bcs,
    'bs': _bcs,
    // one: i = 1 and v = 0; few: v != 0 or n = 0 or n != 1 and n % 100 = 1..19
    // The range starts at 1, so 101, 201 and 1001 are `few`.
    'ro': PluralRuleSet({
      PluralCategory.one: '@i == 1 && @v == 0',
      PluralCategory.few:
          '@v != 0 || @n == 0 || '
          '@n != 1 && @n % 100 >= 1 && @n % 100 <= 19',
    }),
    // one: i = 1 and v = 0 or i = 0 and v != 0 — 0.5 is `one` in Hebrew.
    'he': PluralRuleSet({
      PluralCategory.one: '@i == 1 && @v == 0 || @i == 0 && @v != 0',
      PluralCategory.two: '@i == 2 && @v == 0',
    }),
    // few: n % 100 = 3..10; many: n % 100 = 11..99.
    // A CLDR range matches integers only (UTS #35), so 3.5 is `other`, not
    // `few`. `@v == 0` is what says "integer" in terms of the operands.
    'ar': PluralRuleSet({
      PluralCategory.zero: '@n == 0',
      PluralCategory.one: '@n == 1',
      PluralCategory.two: '@n == 2',
      PluralCategory.few: '@v == 0 && @n % 100 >= 3 && @n % 100 <= 10',
      PluralCategory.many: '@v == 0 && @n % 100 >= 11 && @n % 100 <= 99',
    }),
    // Languages without cardinal categories.
    'ja': PluralRuleSet({}),
    'zh': PluralRuleSet({}),
    'ko': PluralRuleSet({}),
    'th': PluralRuleSet({}),
    'vi': PluralRuleSet({}),
    'id': PluralRuleSet({}),
    'ms': PluralRuleSet({}),
    'ka': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'hu': PluralRuleSet({PluralCategory.one: '@n == 1'}),

    // Every entry below is checked sample by sample against `package:intl`'s
    // own CLDR data by test/plural_matrix_runtime_test.dart, which is what
    // makes hand transcription safe enough to do at all.

    // one: n = 1
    'bg': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'sq': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'eu': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'sw': PluralRuleSet({PluralCategory.one: '@i == 1 && @v == 0'}),
    'af': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'ur': PluralRuleSet({PluralCategory.one: '@i == 1 && @v == 0'}),
    'gl': PluralRuleSet({PluralCategory.one: '@i == 1 && @v == 0'}),
    'ne': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'ml': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'kn': PluralRuleSet({PluralCategory.one: '@i == 0 || @n == 1'}),
    'or': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'ps': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'ta': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'te': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'kk': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'ky': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'uz': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'mn': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'zu': PluralRuleSet({PluralCategory.one: '@i == 0 || @n == 1'}),
    // one: i = 0 or n = 1 — a fraction below one is singular.
    'fa': PluralRuleSet({PluralCategory.one: '@i == 0 || @n == 1'}),
    'bn': PluralRuleSet({PluralCategory.one: '@i == 0 || @n == 1'}),
    'am': PluralRuleSet({PluralCategory.one: '@i == 0 || @n == 1'}),
    'gu': PluralRuleSet({PluralCategory.one: '@i == 0 || @n == 1'}),
    'mr': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    // one: i = 0,1
    'hy': PluralRuleSet({PluralCategory.one: '@i == 0 || @i == 1'}),
    // one: v = 0 and i % 10 = 1 and i % 100 != 11 or f % 10 = 1 and f % 100 != 11
    'mk': PluralRuleSet({
      PluralCategory.one:
          '@v == 0 && @i % 10 == 1 && @i % 100 != 11 || '
          '@f % 10 == 1 && @f % 100 != 11',
    }),
    // one: t = 0 and i % 10 = 1 and i % 100 != 11
    //      or t % 10 = 1 and t % 100 != 11
    'is': PluralRuleSet({
      PluralCategory.one:
          '@t == 0 && @i % 10 == 1 && @i % 100 != 11 || '
          '@t % 10 == 1 && @t % 100 != 11',
    }),
    // one: v = 0 and i % 100 = 1; two: v = 0 and i % 100 = 2;
    // few: v = 0 and i % 100 = 3..4 or v != 0
    'sl': PluralRuleSet({
      PluralCategory.one: '@v == 0 && @i % 100 == 1',
      PluralCategory.two: '@v == 0 && @i % 100 == 2',
      PluralCategory.few:
          '@v == 0 && @i % 100 >= 3 && @i % 100 <= 4 || @v != 0',
    }),
    // Baltic. Latvian has a `zero`, which most implementations drop.
    'lv': PluralRuleSet({
      PluralCategory.zero:
          '@v == 0 && @n % 10 == 0 || '
          '@v == 0 && @n % 100 >= 11 && @n % 100 <= 19 || '
          '@v == 2 && @f % 100 >= 11 && @f % 100 <= 19',
      PluralCategory.one:
          '@v == 0 && @n % 10 == 1 && @n % 100 != 11 || '
          '@v == 2 && @f % 10 == 1 && @f % 100 != 11 || '
          '@v != 2 && @f % 10 == 1',
    }),
    'lt': PluralRuleSet({
      PluralCategory.one:
          '@n % 10 == 1 && !(@n % 100 >= 11 && @n % 100 <= 19) && @v == 0',
      PluralCategory.few:
          '@n % 10 >= 2 && @n % 10 <= 9 && '
          '!(@n % 100 >= 11 && @n % 100 <= 19) && @v == 0',
      PluralCategory.many: '@f != 0',
    }),
    // one: n % 10 = 1 and n % 100 != 11; few: n % 10 = 2..4 and
    // n % 100 != 12..14; many: everything else with no fraction.
    'be': PluralRuleSet({
      PluralCategory.one: '@v == 0 && @n % 10 == 1 && @n % 100 != 11',
      PluralCategory.few:
          '@v == 0 && @n % 10 >= 2 && @n % 10 <= 4 && '
          '!(@n % 100 >= 12 && @n % 100 <= 14)',
      PluralCategory.many:
          '@v == 0 && @n % 10 == 0 || '
          '@v == 0 && @n % 10 >= 5 && @n % 10 <= 9 || '
          '@v == 0 && @n % 100 >= 11 && @n % 100 <= 14',
    }),
    // Catalan matches Italian: one plus the whole millions.
    'ca': PluralRuleSet({
      PluralCategory.one: '@i == 1 && @v == 0',
      PluralCategory.many: _millions,
    }),
    // Filipino: one covers 1, 2, 3 and anything not ending in 4, 6 or 9.
    'fil': PluralRuleSet({
      PluralCategory.one:
          '@v == 0 && (@i == 1 || @i == 2 || @i == 3) || '
          '@v == 0 && @i % 10 != 4 && @i % 10 != 6 && @i % 10 != 9 || '
          '@v != 0 && @f % 10 != 4 && @f % 10 != 6 && @f % 10 != 9',
    }),
    // More languages without cardinal categories.
    'km': PluralRuleSet({}),
    'my': PluralRuleSet({}),
    'lo': PluralRuleSet({}),
    'si': PluralRuleSet({
      PluralCategory.one: '@n == 0 || @n == 1 || @i == 0 && @f == 1',
    }),
  };

  /// `many` for the Romance languages: whole millions.
  ///
  /// CLDR writes `e = 0 and i != 0 and i % 1000000 = 0 and v = 0`. The `e`
  /// operand is the exponent of a compact form (`1M` has e = 6); nothing
  /// here formats compactly before selecting a branch, so e is always 0 and
  /// the clause is left out rather than carried as a constant true.
  static const String _millions = '@i != 0 && @i % 1000000 == 0 && @v == 0';

  static const PluralRuleSet _slavic = PluralRuleSet({
    PluralCategory.one: '@v == 0 && @i % 10 == 1 && @i % 100 != 11',
    PluralCategory.few:
        '@v == 0 && @i % 10 >= 2 && @i % 10 <= 4 && '
        '!(@i % 100 >= 12 && @i % 100 <= 14)',
    PluralCategory.many:
        '@v == 0 && @i % 10 == 0 || '
        '@v == 0 && @i % 10 >= 5 && @i % 10 <= 9 || '
        '@v == 0 && @i % 100 >= 11 && @i % 100 <= 14',
  });

  static const PluralRuleSet _westSlavic = PluralRuleSet({
    PluralCategory.one: '@i == 1 && @v == 0',
    PluralCategory.few: '@i >= 2 && @i <= 4 && @v == 0',
    PluralCategory.many: '@v != 0',
  });

  static const PluralRuleSet _bcs = PluralRuleSet({
    PluralCategory.one:
        '@v == 0 && @i % 10 == 1 && @i % 100 != 11 || '
        '@f % 10 == 1 && @f % 100 != 11',
    PluralCategory.few:
        '@v == 0 && @i % 10 >= 2 && @i % 10 <= 4 && '
        '!(@i % 100 >= 12 && @i % 100 <= 14) || '
        '@f % 10 >= 2 && @f % 10 <= 4 && !(@f % 100 >= 12 && @f % 100 <= 14)',
  });

  /// Ordinal rules, used by `selectordinal`.
  ///
  /// A different CLDR table from the cardinal ones, and not derivable from
  /// them: English is `one/two/few/other` for ordinals but only `one/other`
  /// for cardinals, while Slovenian is the reverse.
  ///
  /// Some of these are written over `n` and some over `i`, exactly as CLDR
  /// writes them, and the difference is visible: English `1.5` is `other`
  /// because the rule reads `n % 10 = 1`, while Azerbaijani `1.5` is `one`
  /// because its rule reads `i % 10 = 1`. Both are nonsense input — there is
  /// no 1.5th of anything — but they are ICU's nonsense, and matching it is
  /// cheaper than explaining a difference.
  ///
  /// `package:intl` ships no ordinal table, so unlike the cardinal rules
  /// these cannot be checked against it. They are checked against ICU
  /// instead, through a vendored dump in `test/data/cldr_ordinals.json`;
  /// `tool/ordinal_oracle.sh` regenerates it.
  ///
  /// A language is listed only when its ordinal rule is known, so that an
  /// unlisted one produces a diagnostic instead of English behaviour.
  static const Map<String, PluralRuleSet> _ordinalRules = {
    // The widest ordinal rule CLDR has: `few` keys off whole hundreds
    // below a thousand, so 100 and 1100 are `few` and 1000 is not.
    'az': PluralRuleSet({
      PluralCategory.one:
          '@i % 10 == 1 || @i % 10 == 2 || @i % 10 == 5 || '
          '@i % 10 == 7 || @i % 10 == 8 || '
          '@i % 100 == 20 || @i % 100 == 50 || @i % 100 == 70 || '
          '@i % 100 == 80',
      PluralCategory.few:
          '@i % 10 == 3 || @i % 10 == 4 || '
          '@i % 1000 == 100 || @i % 1000 == 200 || @i % 1000 == 300 || '
          '@i % 1000 == 400 || @i % 1000 == 500 || @i % 1000 == 600 || '
          '@i % 1000 == 700 || @i % 1000 == 800 || @i % 1000 == 900',
      PluralCategory.many:
          '@i == 0 || @i % 10 == 6 || '
          '@i % 100 == 40 || @i % 100 == 60 || @i % 100 == 90',
    }),
    'be': PluralRuleSet({
      PluralCategory.few:
          '(@n % 10 == 2 || @n % 10 == 3) && '
          '@n % 100 != 12 && @n % 100 != 13',
    }),
    // Bengali counts 10 as `one`; Odia, with otherwise the same rule,
    // does not.
    'bn': PluralRuleSet({
      PluralCategory.one:
          '@n == 1 || @n == 5 || @n == 7 || @n == 8 || @n == 9 || '
          '@n == 10',
      PluralCategory.two: '@n == 2 || @n == 3',
      PluralCategory.few: '@n == 4',
      PluralCategory.many: '@n == 6',
    }),
    'ca': PluralRuleSet({
      PluralCategory.one: '@n == 1 || @n == 3',
      PluralCategory.two: '@n == 2',
      PluralCategory.few: '@n == 4',
    }),
    // 1st, 2nd, 3rd, 4th. Written over `n`, so 1.5 is `other`: there is
    // no 1.5th of anything.
    'en': PluralRuleSet({
      PluralCategory.one: '@n % 10 == 1 && @n % 100 != 11',
      PluralCategory.two: '@n % 10 == 2 && @n % 100 != 12',
      PluralCategory.few: '@n % 10 == 3 && @n % 100 != 13',
    }),
    'fil': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'fr': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'gu': PluralRuleSet({
      PluralCategory.one: '@n == 1',
      PluralCategory.two: '@n == 2 || @n == 3',
      PluralCategory.few: '@n == 4',
      PluralCategory.many: '@n == 6',
    }),
    'hi': PluralRuleSet({
      PluralCategory.one: '@n == 1',
      PluralCategory.two: '@n == 2 || @n == 3',
      PluralCategory.few: '@n == 4',
      PluralCategory.many: '@n == 6',
    }),
    'hu': PluralRuleSet({PluralCategory.one: '@n == 1 || @n == 5'}),
    'hy': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    // 8, 11, 80 and 800 exactly; 88 and 180 are not.
    'it': PluralRuleSet({
      PluralCategory.many: '@n == 11 || @n == 8 || @n == 80 || @n == 800',
    }),
    // `many` swallows most of the first hundred; `one` is only 1.
    'ka': PluralRuleSet({
      PluralCategory.one: '@i == 1',
      PluralCategory.many:
          '@i == 0 || @i % 100 >= 2 && @i % 100 <= 20 || '
          '@i % 100 == 40 || @i % 100 == 60 || @i % 100 == 80',
    }),
    // `many` for 6, 9 and whole tens, but not for zero.
    'kk': PluralRuleSet({
      PluralCategory.many:
          '@n % 10 == 6 || @n % 10 == 9 || @n % 10 == 0 && @n != 0',
    }),
    'lo': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    // Like English but over `i`, and with a `many` for 7 and 8.
    'mk': PluralRuleSet({
      PluralCategory.one: '@i % 10 == 1 && @i % 100 != 11',
      PluralCategory.two: '@i % 10 == 2 && @i % 100 != 12',
      PluralCategory.many:
          '(@i % 10 == 7 || @i % 10 == 8) && '
          '@i % 100 != 17 && @i % 100 != 18',
    }),
    'mr': PluralRuleSet({
      PluralCategory.one: '@n == 1',
      PluralCategory.two: '@n == 2 || @n == 3',
      PluralCategory.few: '@n == 4',
    }),
    'ms': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    // one: n = 1..4. A CLDR range matches integers only, hence `@v == 0`.
    'ne': PluralRuleSet({PluralCategory.one: '@v == 0 && @n >= 1 && @n <= 4'}),
    'or': PluralRuleSet({
      PluralCategory.one: '@n == 1 || @n == 5 || @n == 7 || @n == 8 || @n == 9',
      PluralCategory.two: '@n == 2 || @n == 3',
      PluralCategory.few: '@n == 4',
      PluralCategory.many: '@n == 6',
    }),
    'ro': PluralRuleSet({PluralCategory.one: '@n == 1'}),
    'sq': PluralRuleSet({
      PluralCategory.one: '@n == 1',
      PluralCategory.many: '@n % 10 == 4 && @n % 100 != 14',
    }),
    'sv': PluralRuleSet({
      PluralCategory.one:
          '(@n % 10 == 1 || @n % 10 == 2) && '
          '@n % 100 != 11 && @n % 100 != 12',
    }),
    'uk': PluralRuleSet({PluralCategory.few: '@n % 10 == 3 && @n % 100 != 13'}),
    'vi': PluralRuleSet({PluralCategory.one: '@n == 1'}),

    // Languages whose ordinals have no categories at all: one form,
    // whatever the number. Listed rather than defaulted, so that a
    // language absent from this map is absent on purpose.
    'af': _ordinalOther,
    'am': _ordinalOther,
    'ar': _ordinalOther,
    'bg': _ordinalOther,
    'bs': _ordinalOther,
    'cs': _ordinalOther,
    'da': _ordinalOther,
    'de': _ordinalOther,
    'el': _ordinalOther,
    'es': _ordinalOther,
    'et': _ordinalOther,
    'eu': _ordinalOther,
    'fa': _ordinalOther,
    'fi': _ordinalOther,
    'gl': _ordinalOther,
    'he': _ordinalOther,
    'hr': _ordinalOther,
    'id': _ordinalOther,
    'is': _ordinalOther,
    'ja': _ordinalOther,
    'km': _ordinalOther,
    'kn': _ordinalOther,
    'ko': _ordinalOther,
    'ky': _ordinalOther,
    'lt': _ordinalOther,
    'lv': _ordinalOther,
    'ml': _ordinalOther,
    'mn': _ordinalOther,
    'my': _ordinalOther,
    'nb': _ordinalOther,
    'nl': _ordinalOther,
    'no': _ordinalOther,
    'pl': _ordinalOther,
    'ps': _ordinalOther,
    'pt': _ordinalOther,
    'ru': _ordinalOther,
    'si': _ordinalOther,
    'sk': _ordinalOther,
    'sl': _ordinalOther,
    'sr': _ordinalOther,
    'sw': _ordinalOther,
    'ta': _ordinalOther,
    'te': _ordinalOther,
    'th': _ordinalOther,
    'tr': _ordinalOther,
    'ur': _ordinalOther,
    'uz': _ordinalOther,
    'zh': _ordinalOther,
    'zu': _ordinalOther,
  };

  static const PluralRuleSet _ordinalOther = PluralRuleSet({});

  /// Cardinal rules for [language], or `null` when it is not in the table.
  static PluralRuleSet? forLanguage(String language) => _rules[language];

  /// Ordinal rules for [language], or `null` when they are not known.
  static PluralRuleSet? ordinalForLanguage(String language) =>
      _ordinalRules[language];

  /// Every language with cardinal rules, sorted, for diagnostics.
  static List<String> get supportedLanguages =>
      _rules.keys.toList(growable: false)..sort();

  /// Every language with ordinal rules, sorted, for diagnostics.
  static List<String> get supportedOrdinalLanguages =>
      _ordinalRules.keys.toList(growable: false)..sort();
}
