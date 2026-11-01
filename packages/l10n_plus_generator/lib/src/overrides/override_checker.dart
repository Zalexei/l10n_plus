import 'package:l10n_plus/l10n_plus.dart';

import '../ast/message_ast.dart';
import '../diagnostic.dart';
import '../plural/cldr_plural_rules.dart';
import '../rich/rich_key.dart';
import 'override_bundle.dart';
import 'override_fingerprint.dart';
import 'override_schema.dart';

/// Validates an override bundle against the lookups the project emitted.
///
/// This is the keystone of the feature rather than an extra. The whole claim
/// of this library is that a localization mistake belongs at build time, and a
/// bundle downloaded at run time is the one place that claim could quietly
/// stop being true: a misspelled key, a branch the locale does not have, a
/// placeholder the message never took — each of them renders as wrong text on
/// a screen and nothing anywhere says so.
///
/// So every check here answers a question with the project in hand, and the
/// one it answers that nothing else in the field can is the branch: `few` is a
/// real CLDR category and a real mistake in English, and knowing that needs
/// the same 222 language table the generator compiles its conditions from.
abstract final class OverrideChecker {
  /// Reports everything wrong with [bundles], which are one release.
  ///
  /// A directory of bundles is checked as a unit rather than one file at a
  /// time, because one question only exists at that scale: two bundles can
  /// claim one locale — an `en.json` left beside an `overrides_en.json` — and
  /// then which of them the application installs is decided by whatever serves
  /// them rather than by anything here. Per-file checking cannot see it, and
  /// the bundle that loses is often the one that was just translated.
  ///
  /// A locale with no bundle at all is the other thing only this scale sees,
  /// and it is reported by the caller: not overriding a locale is normal, so
  /// it is information about a run rather than a fault in a file.
  static void checkAll({
    required List<OverrideBundle> bundles,
    required OverrideCatalog catalog,
    required DiagnosticCollector diagnostics,
    bool requireFingerprint = true,
  }) {
    final seen = <String, OverrideBundle>{};
    for (final bundle in bundles) {
      final first = seen[bundle.localeTag];
      if (first == null) {
        seen[bundle.localeTag] = bundle;
      } else {
        diagnostics.add(
          Diagnostic.error(
            code: 'duplicate_override_locale',
            message:
                'Two bundles here are for "${bundle.localeTag}": '
                '"${first.path}" and "${bundle.path}".',
            span: bundle.localeSpan ?? bundle.rootSpan,
            details:
                'A locale has one overridable surface, and the application '
                'installs one bundle for it. Which of these two takes effect '
                'is decided by whatever serves them, so both passing this '
                'check says nothing about which text ships.\n'
                'The locale comes from "@@locale", or from the file name when '
                'the file states none. Remove the bundle that is not '
                'shipping, or move it out of this directory.',
          ),
        );
      }
      // Checked anyway, duplicate or not: a report naming one of six mistakes
      // costs six round trips, and that is as true of six files as of one.
      check(
        bundle: bundle,
        catalog: catalog,
        diagnostics: diagnostics,
        requireFingerprint: requireFingerprint,
      );
    }
  }

  /// Reports everything wrong with [bundle] against [catalog].
  ///
  /// Reports as much as it can rather than stopping at the first problem: a
  /// bundle comes back from one round trip, and a report naming one of six
  /// mistakes costs six round trips.
  /// [requireFingerprint] is false when the caller is about to write one:
  /// `--stamp` re-checks a bundle against this build and signs it, so
  /// complaining that it is unsigned would be a complaint about the thing the
  /// command is doing.
  static void check({
    required OverrideBundle bundle,
    required OverrideCatalog catalog,
    required DiagnosticCollector diagnostics,
    bool requireFingerprint = true,
  }) {
    final schema = catalog.forLocale(bundle.localeTag);
    if (schema == null) {
      diagnostics.add(
        Diagnostic.error(
          code: 'unknown_override_locale',
          message:
              'This project has no "${bundle.localeTag}" locale to override.',
          // The whole object when the file declared no "@@locale", so the
          // report still says which file. A bundle named after its locale is
          // the normal shape in a directory of them, and a report of twelve
          // that cannot name the one that is wrong is a hunt.
          span: bundle.localeSpan ?? bundle.rootSpan,
          details:
              'Locales:\n'
              '${catalog.localeTags.map((tag) => '  $tag').join('\n')}',
        ),
      );
      return;
    }

    if (requireFingerprint) {
      _checkFingerprint(
        bundle: bundle,
        schema: schema,
        diagnostics: diagnostics,
      );
    }

    for (final message in bundle.messages) {
      _checkMessage(message: message, schema: schema, diagnostics: diagnostics);
    }
  }

  /// Reports a bundle that was checked against a different build, or none.
  ///
  /// The one check here that is not about the bundle's contents. Everything
  /// else this class does is an answer about the project as it stands now, and
  /// a bundle carries no record of the project it was written for — so a
  /// message that gained a nested choice leaves yesterday's bundle naming
  /// branches that all still exist and mean something else. The fingerprint is
  /// that record.
  static void _checkFingerprint({
    required OverrideBundle bundle,
    required OverrideSchema schema,
    required DiagnosticCollector diagnostics,
  }) {
    final expected = OverrideFingerprint.of(schema);
    final declared = bundle.fingerprint;
    if (declared == null) {
      diagnostics.add(
        Diagnostic.error(
          code: 'missing_override_fingerprint',
          message:
              'The bundle does not say which build it was checked '
              'against.',
          span: bundle.firstMemberSpan ?? bundle.rootSpan,
          details:
              'Every other answer in this report is an answer about this '
              'project as it stands, and a bundle outlives a build. Branches '
              'of a nested choice are addressed by position — "0/one" is the '
              'first choice\'s "one" branch — so a message that gains a '
              'choice renumbers the ones after it while every name in an old '
              'bundle still exists.\n'
              'Write it with --stamp, or by hand:\n'
              '  "${L10nOverrides.fingerprintKey}": "$expected"',
        ),
      );
      return;
    }
    if (declared == expected) return;
    diagnostics.add(
      Diagnostic.error(
        code: 'override_fingerprint_mismatch',
        message: 'This bundle was checked against another build.',
        span: bundle.fingerprintSpan,
        details:
            'It states the surface $declared, and this build compiled '
            '$expected: a key, a branch, a placeholder or the position of a '
            'nested choice is not what it was when the bundle was written. '
            'The texts may every one of them still be right — nothing in them '
            'can say so, which is why this is checked here and refused by '
            '"installOverrides" rather than discovered on a screen.\n'
            'Re-run with --stamp once the rest of this report is clean: it '
            'checks the bundle against this build and writes the new '
            'fingerprint.',
      ),
    );
  }

  static void _checkMessage({
    required OverrideBundleMessage message,
    required OverrideSchema schema,
    required DiagnosticCollector diagnostics,
  }) {
    // A rich key carries its `(rich)` suffix, and a bundle naturally writes
    // the name without it. Both spellings are looked up, so the answer is
    // "this cannot be overridden" either way rather than "no such key" for
    // one of them.
    final target =
        schema.messages[message.key] ??
        schema.messages['${message.key}${RichKey.suffix}'];
    if (target == null) {
      final nearest = _nearestKey(message.key, schema.messages.keys);
      diagnostics.add(
        Diagnostic.error(
          code: 'unknown_override_key',
          message: 'This project defines no message "${message.key}".',
          span: message.keySpan,
          details:
              '${nearest == null ? '' : 'Did you mean "$nearest"?\n'}'
              'An override key is the dotted translation key, not the Dart '
              'member path. A key that does not exist yet is a release, not '
              'an override.',
        ),
      );
      return;
    }

    if (target.isRich) {
      diagnostics.add(
        Diagnostic.error(
          code: 'override_rich_unsupported',
          message: 'A rich message cannot be overridden.',
          span: message.keySpan,
          translationKey: message.key,
          details:
              'The tags of "${message.key}" are structure, not text: the '
              'generated signature takes one builder per tag, so changing '
              'them changes the API. There is nothing here for a text to be '
              'the text of.\n'
              'Reword the plain messages around it, or ship a release.',
        ),
      );
      return;
    }

    if (!target.hasPlainSlot && !message.branched) {
      diagnostics.add(
        Diagnostic.error(
          code: 'override_needs_branches',
          message:
              '"${message.key}" is chosen per branch, so it needs one '
              'text per branch.',
          span: message.keySpan,
          translationKey: message.key,
          details:
              'One text cannot stand in for every branch: that is how a '
              'plural silently stops pluralizing. The runtime ignores it, and '
              'this is where you find out.\n'
              '${_branchHelp(target)}',
        ),
      );
      return;
    }

    if (!target.hasBranchSlots && message.branched) {
      diagnostics.add(
        Diagnostic.error(
          code: 'override_takes_no_branches',
          message: '"${message.key}" has one form, so it takes one text.',
          span: message.keySpan,
          translationKey: message.key,
          details:
              'Nothing branches on it, so there is no branch to key a text '
              'by. Write the text itself:\n'
              '  "${message.key}": "…"',
        ),
      );
      return;
    }

    for (final text in message.texts) {
      final slot = target.slotOf(text.branch);
      if (slot == null) {
        diagnostics.add(
          Diagnostic.error(
            code: 'unknown_override_branch',
            message:
                '"${text.branch}" is not a branch of "${message.key}" in '
                '${schema.localeTag}.',
            span: text.nameSpan,
            translationKey: message.key,
            details: _branchDetails(text.branch!, target, schema),
          ),
        );
        continue;
      }
      _checkText(
        text: text,
        slot: slot,
        key: message.key,
        diagnostics: diagnostics,
      );
    }
  }

  /// The ICU form an override must not be written in.
  ///
  /// `{name, …` is an argument with a type, which is the whole of ICU that
  /// matters here: `{count, plural, …}`, `{gender, select, …}` and
  /// `{amount, number, currency}` all start this way and all mean somebody
  /// thought the text was a message.
  static final RegExp _icu = RegExp(r'\{\s*[A-Za-z_][A-Za-z0-9_.]*\s*,');

  static void _checkText({
    required OverrideBundleText text,
    required OverrideSlot slot,
    required String key,
    required DiagnosticCollector diagnostics,
  }) {
    final icu = _icu.firstMatch(text.value);
    if (icu != null) {
      diagnostics.add(
        Diagnostic.error(
          code: 'override_contains_icu',
          message: 'An override carries text, not ICU.',
          span: text.spanAt(icu.start, icu.end - icu.start),
          translationKey: key,
          details:
              'Selecting a branch and formatting a value are compiled into '
              'the application: the plural rules of 222 languages are Dart '
              'conditions and every number goes through package:intl. Nothing '
              'at run time can read this, so its rules would be ignored and '
              'its braces would print.\n'
              'Write the text of one branch, with ${_tokenHelp(slot)}',
        ),
      );
      return;
    }

    final template = text.value;
    var reportedNumberSign = false;
    var index = 0;
    while (index < template.length) {
      final unit = template.codeUnitAt(index);
      if (unit == 0x23) {
        if (!slot.tokens.contains('#') && !reportedNumberSign) {
          reportedNumberSign = true;
          diagnostics.add(
            Diagnostic.error(
              code: 'override_unexpected_number_sign',
              message: '"#" is the plural count, and this message has none.',
              span: text.spanAt(index, 1),
              translationKey: key,
              details:
                  'Nothing would replace it, so it would print as a hash. '
                  'Write the digits, or ${_tokenHelp(slot)}',
            ),
          );
        }
        index++;
        continue;
      }
      if (unit == 0x7b) {
        final end = template.indexOf('}', index + 1);
        if (end > index) {
          final name = template.substring(index + 1, end);
          if (L10nOverrides.isToken(name)) {
            if (!slot.tokens.contains(name)) {
              diagnostics.add(
                Diagnostic.error(
                  code: 'unknown_override_placeholder',
                  message: '"$key" takes no placeholder "$name".',
                  span: text.spanAt(index, end + 1 - index),
                  translationKey: key,
                  details:
                      'A placeholder the message does not take is a signature '
                      'change, which is a release. This one would print as '
                      '"{$name}".\n'
                      'Here you can write ${_tokenHelp(slot)}',
                ),
              );
            }
            index = end + 1;
            continue;
          }
        }
      }
      index++;
    }
  }

  /// What a slot's tokens are, as a sentence ending in a full stop.
  static String _tokenHelp(OverrideSlot slot) {
    if (slot.tokens.isEmpty) return 'no placeholder at all.';
    final names = slot.tokens.toList()..sort();
    return '${names.map((name) => name == '#' ? '"#"' : '"{$name}"').join(', ')}.';
  }

  /// Which branches a message has, for the diagnostic that lists them.
  static String _branchHelp(OverrideMessage message) {
    final names = message.branchNames;
    if (names.isEmpty) return 'It has no branches.';
    return 'Branches of "${message.key}":\n'
        '${names.map((name) => '  $name').join('\n')}';
  }

  /// Why a branch name is wrong, with CLDR consulted when it is a category.
  ///
  /// The distinction worth drawing: `two` in English is not a typo, it is a
  /// category English does not have, and no message in English can ever have
  /// a branch for it. Saying that needs the plural tables, which is why this
  /// check exists in a generator and not in a schema validator.
  static String _branchDetails(
    String branch,
    OverrideMessage message,
    OverrideSchema schema,
  ) {
    // A nested choice prefixes its branches with its number, so the category
    // to judge is the last segment.
    final segments = branch.split('/');
    final label = segments.last;
    final prefix = segments.length > 1 ? segments.first : '';
    final buffer = StringBuffer();
    final available = message.pluralCategories[prefix];
    if (PluralCategory.tryParse(label) != null &&
        available != null &&
        available.isNotEmpty &&
        !available.contains(label)) {
      // The categories of *this* choice: cardinal and ordinal are different
      // tables, and English ranks with `two` while it counts without it.
      final names = available.toList(growable: false)..sort();
      buffer.writeln(
        'CLDR ${CldrPluralRules.cldrVersion} gives "${schema.language}" the '
        'categories ${names.join(', ')} here, so nothing in it can select a '
        '"$label" branch.',
      );
    }
    if (branch.contains('/')) {
      buffer.writeln(
        'A branch of a nested choice carries that choice\'s number, counted '
        'from zero in the order the message states them.',
      );
    }
    buffer.write(_branchHelp(message));
    return buffer.toString();
  }

  /// The key [written] is most likely a typo of, or `null`.
  ///
  /// The same budget the configuration uses for its own keys: a third of the
  /// length and at most three edits, so a near miss gets an answer and an
  /// unrelated key gets the list instead of a wrong guess.
  static String? _nearestKey(String written, Iterable<String> known) {
    String? best;
    var bestDistance = 1 << 30;
    for (final candidate in known) {
      final distance = _editDistance(written, candidate);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    final budget = (written.length / 3).floor().clamp(1, 3);
    return bestDistance <= budget ? best : null;
  }

  static int _editDistance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + cost;
        current[j] = deletion < insertion ? deletion : insertion;
        if (substitution < current[j]) current[j] = substitution;
      }
      previous = current;
    }
    return previous[b.length];
  }
}
