// Regenerates the CLDR plural tables from the published CLDR data.
//
//   dart run tool/update_cldr_plural_rules.dart
//   dart run tool/update_cldr_plural_rules.dart --cldr 49
//   dart run tool/update_cldr_plural_rules.dart --from path/to/cldr-core
//
// The release is pinned, not `@latest`. `@latest` moved to CLDR 49 while the
// tables said 48, so a run meant to change one entry would have rewritten all
// of them -- silently, because the version in the generated file is read from
// the data. Taking a new release is now typing its number, and whatever
// arrives is checked against what was asked for.
//
// Writes two files:
//
//   lib/src/plural/cldr_plural_rules.dart   the cardinal and ordinal tables
//   test/cldr_plural_samples.dart           CLDR's own @integer/@decimal
//                                           samples, for the table's test
//
// Nothing in the package imports this tool; it exists so that the tables can
// be rebuilt when a new CLDR lands, rather than being a hand written dump
// nobody dares to touch.
library;

import 'dart:convert';
import 'dart:io';

/// The CLDR release the committed tables were generated from.
///
/// Changing this number is how a CLDR upgrade starts, and it belongs in the
/// same commit as the regenerated tables: the generated file states the
/// version it was built from, so the two can only disagree by accident.
const String _pinnedCldr = '48';

/// Where the CLDR JSON is fetched from when `--from` is not given.
String _cdn(String version) =>
    'https://cdn.jsdelivr.net/npm/cldr-core@$version/supplemental';

/// CLDR categories in the order the generated `if` chain must evaluate them.
const List<String> _categoryOrder = ['zero', 'one', 'two', 'few', 'many'];

/// The operand test standing for "n is an integer".
///
/// CLDR ranges match integer values only (UTS #35), so `n % 100 = 3..10` is
/// false for 3.5 and true for 3. `i` is the integer digits of `n`, so `n == i`
/// says exactly that, and says it without depending on how the number was
/// spelled.
const String _integral = '@n == @i';

Future<void> main(List<String> arguments) async {
  final fromIndex = arguments.indexOf('--from');
  final from = fromIndex == -1 ? null : arguments[fromIndex + 1];
  final cldrIndex = arguments.indexOf('--cldr');
  final wanted = cldrIndex == -1 ? _pinnedCldr : arguments[cldrIndex + 1];

  final cardinalJson = await _load('plurals.json', from, wanted);
  final ordinalJson = await _load('ordinals.json', from, wanted);

  final cardinalRoot =
      jsonDecode(cardinalJson)['supplemental'] as Map<String, dynamic>;
  final ordinalRoot =
      jsonDecode(ordinalJson)['supplemental'] as Map<String, dynamic>;
  final version = _versionOf(cardinalRoot, 'plurals.json', wanted);
  _versionOf(ordinalRoot, 'ordinals.json', wanted);

  final cardinal = _read(
    cardinalRoot['plurals-type-cardinal'] as Map<String, dynamic>,
  );
  final ordinal = _read(
    ordinalRoot['plurals-type-ordinal'] as Map<String, dynamic>,
  );

  File('lib/src/plural/cldr_plural_rules.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(_rulesLibrary(version, cardinal, ordinal));
  File('test/cldr_plural_samples.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(_samplesLibrary(version, cardinal, ordinal));

  stdout
    ..writeln('CLDR $version')
    ..writeln('  cardinal: ${cardinal.length} entries')
    ..writeln('  ordinal:  ${ordinal.length} entries')
    ..writeln('Run `dart format .` and `UPDATE_GOLDENS=1 dart test` next.');
  if (version != _pinnedCldr) {
    stdout.writeln(
      'This is not the pinned release $_pinnedCldr. Set _pinnedCldr to '
      '$version in this file, in the same commit as the tables.',
    );
  }
}

/// The release the data says it is, which must be the release that was asked
/// for.
///
/// Both files are checked, and `--from` is checked too: a directory holding
/// another release is the same mistake as a moving `@latest`, and it is the
/// one actually made while this tool was being changed.
String _versionOf(Map<String, dynamic> root, String file, String wanted) {
  final version =
      (root['version'] as Map<String, dynamic>)['_cldrVersion'] as String;
  if (version != wanted) {
    throw StateError(
      '$file is CLDR $version, not the $wanted that was asked for. '
      'Pass --cldr $version to take that release deliberately.',
    );
  }
  return version;
}

Future<String> _load(String name, String? from, String version) async {
  if (from != null) return File('$from/$name').readAsStringSync();
  final cdn = _cdn(version);
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$cdn/$name'));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('GET $cdn/$name -> ${response.statusCode}');
    }
    return response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

/// One language's rules, as parsed out of the CLDR JSON.
final class _Language {
  _Language(this.tag);

  final String tag;

  /// CLDR condition text per category, `other` excluded.
  final Map<String, String> conditions = {};

  /// Sample values per category, `other` included.
  final Map<String, List<String>> samples = {};
}

/// Reads one CLDR plural table, dropping what this generator cannot key on.
Map<String, _Language> _read(Map<String, dynamic> table) {
  final result = <String, _Language>{};
  for (final entry in table.entries) {
    // Script and region qualified entries (`pt-PT`, `kok-Latn`) are kept:
    // `pt-PT` is the one entry in either table whose rules are not its
    // language's, and the lookup reaches it through the locale's lineage.
    final language = _Language(entry.key);
    final rules = entry.value as Map<String, dynamic>;
    for (final category in [..._categoryOrder, 'other']) {
      final text = rules['pluralRule-count-$category'] as String?;
      if (text == null) continue;
      final condition = _conditionText(text);
      if (condition.isNotEmpty && category != 'other') {
        language.conditions[category] = condition;
      }
      language.samples[category] = _samples(text);
    }
    result[entry.key] = language;
  }
  return result;
}

/// The rule text with its `@integer`/`@decimal` sample lists removed.
String _conditionText(String rule) =>
    rule.split(RegExp('@integer|@decimal')).first.trim();

// ---------------------------------------------------------------------------
// Conditions
// ---------------------------------------------------------------------------

/// Sentinels for a relation that is constant once `e` is known to be zero.
const String _true = '<true>';
const String _false = '<false>';

/// Converts one CLDR condition into a Dart expression over [PluralOperands].
///
/// `and` binds tighter than `or` in CLDR and `&&` binds tighter than `||` in
/// Dart, so the two nest identically and no parentheses are needed between
/// them. Only a relation that expands to several terms is bracketed.
String convertCondition(String cldr) {
  final disjuncts = <String>[];
  for (final orPart in cldr.split(' or ')) {
    final conjuncts = <String>[];
    var dead = false;
    for (final andPart in orPart.split(' and ')) {
      final term = convertRelation(andPart.trim());
      if (term == _true) continue;
      if (term == _false) {
        dead = true;
        break;
      }
      conjuncts.add(term);
    }
    if (dead) continue;
    // Every relation of this disjunct was constantly true, so the rule is.
    if (conjuncts.isEmpty) return _true;
    disjuncts.add(conjuncts.join(' && '));
  }
  if (disjuncts.isEmpty) return _false;
  return disjuncts.join(' || ');
}

final RegExp _relation = RegExp(
  r'^([nivwftec])\s*(?:%\s*(\d+))?\s*(!?=)\s*(.+)$',
);

/// Converts one CLDR relation, e.g. `i % 10 = 2..4`.
String convertRelation(String relation) {
  final match = _relation.firstMatch(relation);
  if (match == null) {
    throw FormatException('unparsable CLDR relation', relation);
  }
  final operand = match[1]!;
  final modulus = match[2];
  final negated = match[3] == '!=';
  final items = match[4]!.split(',').map((item) => item.trim()).toList();

  // `e` (and its old spelling `c`) is the exponent of a compact form. Nothing
  // here formats compactly before selecting a branch, so it is always zero and
  // the relation is decided now rather than carried as a constant.
  if (operand == 'e' || operand == 'c') {
    final matches = items.any((item) => _containsValue(item, 0));
    return matches != negated ? _true : _false;
  }

  final expression = modulus == null ? '@$operand' : '@$operand % $modulus';
  // Ranges are the only place the integer rule bites, and only `n` can be
  // fractional — every other operand counts digits.
  final needsGuard = operand == 'n';
  final hasRange = items.any((item) => item.contains('..'));

  if (negated && !hasRange) {
    // `i % 100 != 12,13` reads better as two disequalities than as a negation.
    return items
        .map((item) => '$expression != ${int.parse(item)}')
        .join(' && ');
  }

  final terms = <String>[];
  for (final item in items) {
    final bounds = item.split('..');
    if (bounds.length == 1) {
      terms.add('$expression == ${int.parse(item)}');
      continue;
    }
    final low = int.parse(bounds[0]);
    final high = int.parse(bounds[1]);
    final guard = needsGuard ? '$_integral && ' : '';
    terms.add(
      low == high
          ? '$guard$expression == $low'
          : '$guard$expression >= $low && $expression <= $high',
    );
  }

  if (negated) return '!(${terms.join(' || ')})';
  if (terms.length == 1) return terms.single;
  return '(${terms.join(' || ')})';
}

/// Whether the CLDR range or value [item] contains the integer [value].
bool _containsValue(String item, int value) {
  final bounds = item.split('..');
  if (bounds.length == 1) return int.parse(item) == value;
  return value >= int.parse(bounds[0]) && value <= int.parse(bounds[1]);
}

// ---------------------------------------------------------------------------
// Samples
// ---------------------------------------------------------------------------

/// The sample values of one rule that this runtime can actually be handed.
///
/// Dropped, with the reason each time:
///
/// * `…` — CLDR's "and so on" marker, not a value;
/// * `1c6`, `1.1c6` — compact notation, which selects on the operand `e`
///   this generator never sees;
/// * `1.0`, `0.00` — a whole number written with fraction digits. The API
///   takes a `num`, and `1.0` as a Dart double is indistinguishable from `1`,
///   so CLDR's operands for it (`v = 1`) cannot be reproduced;
/// * anything whose `toString` differs from the sample text, such as `0.10`,
///   for the same reason one step further along.
List<String> _samples(String rule) {
  final values = <String>[];
  for (final part in rule.split(RegExp('@integer|@decimal')).skip(1)) {
    for (final item in part.split(',').map((item) => item.trim())) {
      if (item.isEmpty || item.contains('…') || item.contains('...')) continue;
      if (item.contains('c') || item.contains('e')) continue;
      // A range denotes the values between its ends; the ends themselves are
      // what can be read off it without guessing the step.
      for (final value in item.split('~')) {
        if (_isUsableSample(value)) values.add(value);
      }
    }
  }
  return values;
}

bool _isUsableSample(String text) {
  if (!text.contains('.')) return int.tryParse(text) != null;
  final value = double.tryParse(text);
  if (value == null) return false;
  if (value == value.truncateToDouble()) return false;
  return value.toString() == text;
}

// ---------------------------------------------------------------------------
// Emission
// ---------------------------------------------------------------------------

/// The part of `PluralRuleSet` that reads a category of one value off its own
/// condition, emitted verbatim.
///
/// Written out here rather than assembled from `writeln` calls because it is
/// code rather than data, and a regular expression passed through two layers
/// of Dart string escaping is unreadable in both of them.
const String _exactValueAccessor = r'''
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
''';

/// The lookup the tables are reached through, written out as source.
///
/// A rule set alone is not enough to report with: a `pt_PT` file whose
/// diagnostic says `pt` is naming the other language's rules. So the lookup
/// returns the tag that answered as well.
const String _lookupAccessors = '''
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
''';

String _rulesLibrary(
  Object? version,
  Map<String, _Language> cardinal,
  Map<String, _Language> ordinal,
) {
  final buffer = StringBuffer()
    ..writeln("import 'package:l10n_plus/l10n_plus.dart';")
    ..writeln()
    ..writeln("import '../ast/message_ast.dart';")
    ..writeln()
    ..writeln('/// Cardinal plural rules for one language.')
    ..writeln('///')
    ..writeln(
      '/// Conditions are Dart source fragments in which `@` is a placeholder '
      'for the',
    )
    ..writeln(
      '/// name of the [PluralOperands] variable the generator emits. Keeping '
      'them as',
    )
    ..writeln(
      '/// source means the runtime ships no rule table at all: the generator '
      'inlines',
    )
    ..writeln('/// the condition for the one locale it is generating.')
    ..writeln('final class PluralRuleSet {')
    ..writeln('  /// Creates a rule set.')
    ..writeln('  const PluralRuleSet(this.conditions);')
    ..writeln()
    ..writeln(
      '  /// Condition per category, in evaluation order. Never '
      'contains',
    )
    ..writeln('  /// [PluralCategory.other], which is the fallthrough.')
    ..writeln('  final Map<PluralCategory, String> conditions;')
    ..writeln()
    ..writeln(
      '  /// Categories this language can actually produce, `other` '
      'included.',
    )
    ..writeln('  Set<PluralCategory> get categories => {')
    ..writeln('    ...conditions.keys,')
    ..writeln('    PluralCategory.other,')
    ..writeln('  };')
    ..writeln()
    ..write(_exactValueAccessor)
    ..writeln('}')
    ..writeln()
    ..writeln('/// The CLDR plural rules, whole.')
    ..writeln('///')
    ..writeln('/// Generated from CLDR $version by')
    ..writeln('/// `tool/update_cldr_plural_rules.dart`. Every language CLDR')
    ..writeln('/// publishes is here, so adding a locale to a project never')
    ..writeln('/// stops at the table; a language CLDR does not know still')
    ..writeln('/// gets a diagnostic rather than English rules.')
    ..writeln('///')
    ..writeln('/// Two CLDR subtleties are compiled in rather than left to the')
    ..writeln('/// reader:')
    ..writeln('///')
    ..writeln('/// * a range matches **integers only** (UTS #35), so')
    ..writeln('///   `n % 100 = 3..10` is `few` for 3 and `other` for 3.5.')
    ..writeln('///   `$_integral` is what says "n is an integer" in operands;')
    ..writeln('/// * the operand `e`, the exponent of a compact form, is')
    ..writeln('///   always 0 here because nothing formats compactly before')
    ..writeln('///   selecting a branch. Relations over it are decided at')
    ..writeln('///   generation time and do not reach the output.')
    ..writeln('///')
    ..writeln('///')
    ..writeln('/// Most entries are keyed by language. The few CLDR qualifies')
    ..writeln('/// by script or region are here too, because one of them is')
    ..writeln('/// not its language: `pt-PT` counts `one` for 1 alone where')
    ..writeln('/// `pt` counts it for 0 and 1 both. [cardinalFor] and')
    ..writeln('/// [ordinalFor] walk a locale lineage to find them.')
    ..writeln('abstract final class CldrPluralRules {')
    ..writeln('  /// The CLDR release these tables were generated from.')
    ..writeln("  static const String cldrVersion = '$version';")
    ..writeln();

  _writeTable(
    buffer,
    '_rules',
    'Cardinal rules keyed by language subtag.',
    cardinal,
  );
  buffer.writeln();
  _writeTable(
    buffer,
    '_ordinalRules',
    'Ordinal rules, used by `selectordinal`.\n'
        '///\n'
        '/// A different CLDR table from the cardinal one: English is\n'
        '/// `one/two/few/other` for ordinals but only `one/other` for\n'
        '/// cardinals. Far fewer languages have ordinal rules, and a\n'
        '/// language missing here produces `unknown_ordinal_language`\n'
        '/// rather than silently borrowing English behaviour.',
    ordinal,
  );

  buffer.write(_lookupAccessors);
  return buffer.toString();
}

void _writeTable(
  StringBuffer buffer,
  String name,
  String doc,
  Map<String, _Language> languages,
) {
  buffer.writeln('  /// ${doc.replaceAll('\n', '\n  ')}');
  buffer.writeln('  static const Map<String, PluralRuleSet> $name = {');
  final tags = languages.keys.toList()..sort();
  for (final tag in tags) {
    final language = languages[tag]!;
    if (language.conditions.isEmpty) {
      buffer.writeln("    '$tag': PluralRuleSet({}),");
      continue;
    }
    buffer.writeln("    '$tag': PluralRuleSet({");
    for (final category in _categoryOrder) {
      final cldr = language.conditions[category];
      if (cldr == null) continue;
      final dart = convertCondition(cldr);
      if (dart == _true || dart == _false) {
        throw StateError('$tag $category reduced to a constant: $cldr');
      }
      buffer
        ..writeln('      // $cldr')
        ..writeln("      PluralCategory.$category: '${_escape(dart)}',");
    }
    buffer.writeln('    }),');
  }
  buffer.writeln('  };');
}

String _samplesLibrary(
  Object? version,
  Map<String, _Language> cardinal,
  Map<String, _Language> ordinal,
) {
  final buffer = StringBuffer()
    ..writeln('/// CLDR\'s own plural samples, for checking the rule tables.')
    ..writeln('///')
    ..writeln('/// Generated from CLDR $version by')
    ..writeln('/// `tool/update_cldr_plural_rules.dart`, which is also what')
    ..writeln('/// writes `lib/src/plural/cldr_plural_rules.dart`. The two')
    ..writeln('/// come from the same file for the same reason a golden and')
    ..writeln('/// its fixture do: the samples are CLDR saying what each rule')
    ..writeln('/// is supposed to select, in CLDR\'s words.')
    ..writeln('///')
    ..writeln('/// Values this runtime cannot be handed are left out — compact')
    ..writeln('/// notation (`1c6`), and whole numbers written with fraction')
    ..writeln('/// digits (`1.0`), which a Dart `num` cannot tell from `1`.')
    ..writeln('library;')
    ..writeln();
  _writeSamples(buffer, 'cldrCardinalSamples', 'cardinal', cardinal);
  buffer.writeln();
  _writeSamples(buffer, 'cldrOrdinalSamples', 'ordinal', ordinal);
  return buffer.toString();
}

void _writeSamples(
  StringBuffer buffer,
  String name,
  String kind,
  Map<String, _Language> languages,
) {
  buffer
    ..writeln('/// Language, then $kind category, then the values CLDR lists')
    ..writeln('/// for it.')
    ..writeln('const Map<String, Map<String, List<num>>> $name = {');
  final tags = languages.keys.toList()..sort();
  for (final tag in tags) {
    final language = languages[tag]!;
    final categories = language.samples.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList();
    if (categories.isEmpty) continue;
    buffer.writeln("  '$tag': {");
    for (final entry in categories) {
      buffer.writeln("    '${entry.key}': [${entry.value.join(', ')}],");
    }
    buffer.writeln('  },');
  }
  buffer.writeln('};');
}

String _escape(String value) => value.replaceAll(r'$', r'\$');
