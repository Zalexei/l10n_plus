import 'package:l10n_plus/l10n_plus.dart';
import 'package:path/path.dart' as p;

import '../ast/message_ast.dart';
import '../config.dart';
import '../ast/translation_tree.dart';
import '../diagnostic.dart';
import '../model/argument.dart';
import '../plural/cldr_plural_rules.dart';

/// All parsed messages of a single locale.
final class LocaleMessages {
  /// Creates the parsed view of one translation file.
  LocaleMessages({
    required this.locale,
    required this.uri,
    required this.root,
    required this.messages,
  });

  /// The locale.
  final L10nLocale locale;

  /// Source file the messages came from.
  final Uri uri;

  /// Key tree, used for structural comparison and namespace generation.
  final TranslationGroup root;

  /// Parsed messages keyed by dotted path.
  final Map<String, ParsedMessage> messages;
}

/// Checks every non-base locale against the base locale.
///
/// The base locale defines the generated API, so any structural difference in
/// another locale would produce code that cannot exist. These are errors, not
/// warnings.
abstract final class CrossLocaleValidator {
  /// Validates [others] against [base].
  static void validate({
    required LocaleMessages base,
    required List<LocaleMessages> others,
    required Map<String, MessageSignature> baseSignatures,
    required DiagnosticCollector diagnostics,
    bool fillMissingFromBase = false,
    ExtraKeys extraKeys = ExtraKeys.error,
  }) {
    _checkPluralSupport(base, diagnostics);
    for (final message in base.messages.values) {
      _checkPluralCategories(base, message, diagnostics);
    }

    for (final locale in others) {
      _checkPluralSupport(locale, diagnostics);
      _compareStructure(
        base: base,
        other: locale,
        baseNode: base.root,
        otherNode: locale.root,
        diagnostics: diagnostics,
        fillMissingFromBase: fillMissingFromBase,
        extraKeys: extraKeys,
      );
      for (final entry in baseSignatures.entries) {
        final message = locale.messages[entry.key];
        if (message == null) continue; // Already reported as a missing key.
        _compareSignature(
          key: entry.key,
          baseLocale: base.locale,
          baseSignature: entry.value,
          other: locale,
          message: message,
          diagnostics: diagnostics,
        );
        _checkPluralCategories(locale, message, diagnostics);
      }
    }
  }

  static void _checkPluralSupport(
    LocaleMessages locale,
    DiagnosticCollector diagnostics,
  ) {
    final language = locale.locale.language;
    for (final type in PluralType.values) {
      final known = type == PluralType.ordinal
          ? CldrPluralRules.ordinalForLanguage(language) != null
          : CldrPluralRules.forLanguage(language) != null;
      if (known) continue;

      for (final message in locale.messages.values) {
        final node = _pluralNodes(
          message.body,
        ).where((node) => node.type == type).firstOrNull;
        if (node == null) continue;

        diagnostics.add(
          Diagnostic.error(
            code: type == PluralType.ordinal
                ? 'unknown_ordinal_language'
                : 'unknown_plural_language',
            message:
                'No CLDR ${type == PluralType.ordinal ? 'ordinal ' : ''}'
                'plural rules are known for language "$language".',
            span: node.span,
            translationKey: message.path,
            details: _unknownLanguageDetails(type, language),
          ),
        );
        break;
      }
    }
  }

  /// Explains an unknown language without listing two hundred known ones.
  ///
  /// The tables are the whole of CLDR, so "not supported" almost always means
  /// the locale tag is wrong rather than that the language is exotic — and a
  /// list of every language CLDR publishes would bury that.
  static String _unknownLanguageDetails(PluralType type, String language) {
    final known = type == PluralType.ordinal
        ? CldrPluralRules.supportedOrdinalLanguages
        : CldrPluralRules.supportedLanguages;
    final buffer = StringBuffer()
      ..writeln('${type.label} messages cannot be generated for this locale.')
      ..writeln(
        'CLDR ${CldrPluralRules.cldrVersion} publishes '
        '${type == PluralType.ordinal ? 'ordinal ' : ''}rules for '
        '${known.length} languages and "$language" is not one of them.',
      );
    if (type == PluralType.ordinal &&
        CldrPluralRules.forLanguage(language) != null) {
      buffer.writeln(
        'It does have cardinal rules, so {n, plural, ...} works here and only '
        '{n, selectordinal, ...} does not.',
      );
    } else {
      buffer.writeln('Check the locale tag on the file.');
    }
    return buffer.toString().trimRight();
  }

  /// The one key [otherNode] still calls by its old name, or `null`.
  ///
  /// Renaming a key in the base locale produces two diagnostics per locale —
  /// the new name is missing, the old one is extra — and neither knows about
  /// the other, so one edit becomes 2N errors that a reader has to pair up by
  /// eye. When a namespace has exactly one of each and they are the same kind
  /// of node, a rename is overwhelmingly the reason, and saying so turns the
  /// pair into one finding with the fix in it.
  ///
  /// Deliberately narrow: two missing and two extra keys could be two
  /// renames or four unrelated edits, and guessing wrong would send someone
  /// renaming the wrong key. Those still get the plain diagnostics.
  static ({TranslationNode from, TranslationNode to})? _renameIn(
    TranslationGroup baseNode,
    TranslationGroup otherNode,
  ) {
    final missing = [
      for (final child in baseNode.children)
        if (otherNode.child(child.key) == null) child,
    ];
    if (missing.length != 1) return null;
    final extra = [
      for (final child in otherNode.children)
        if (baseNode.child(child.key) == null) child,
    ];
    if (extra.length != 1) return null;
    final to = missing.single;
    final from = extra.single;
    // A group where the base has a message is `key_kind_mismatch` territory,
    // and calling it a rename would hide a different problem.
    if ((to is TranslationGroup) != (from is TranslationGroup)) return null;
    return (from: from, to: to);
  }

  /// One finding for a key that changed name in the base locale.
  static Diagnostic _renameDiagnostic({
    required LocaleMessages base,
    required LocaleMessages other,
    required TranslationNode from,
    required TranslationNode to,
    required bool severe,
  }) {
    final covered = messageCount(to);
    final message =
        'Key "${from.key}" looks renamed to "${to.key}" in '
        '${base.locale.toFileTag()}.';
    final details =
        'Base locale ${base.locale.toFileTag()}: '
        '${_where(to)}\n'
        '${other.locale.toFileTag()} locale: '
        '${_where(from)}\n'
        '${covered == 1 ? '' : 'It covers $covered messages.\n'}'
        'They are the only difference in '
        '"${to.path.contains('.') ? to.path.substring(0, to.path.lastIndexOf('.')) : 'the root'}", '
        'so rename it here too. If they are unrelated, add "${to.key}" and '
        'remove "${from.key}" and each will be reported on its own.';
    return severe
        ? Diagnostic.error(
            code: 'renamed_key',
            message: message,
            span: from.keySpan,
            translationKey: from.path,
            details: details,
          )
        : Diagnostic.warning(
            code: 'renamed_key',
            message: message,
            span: from.keySpan,
            translationKey: from.path,
            details: details,
          );
  }

  /// `file.json:12`, or just the line when the span has no file.
  static String _where(TranslationNode node) {
    final source = node.keySpan.sourceUrl;
    final line = node.keySpan.start.line + 1;
    return source == null
        ? '${node.path} (line $line)'
        : '${node.path} (${p.basename(source.path)}:$line)';
  }

  static void _compareStructure({
    required LocaleMessages base,
    required LocaleMessages other,
    required TranslationGroup baseNode,
    required TranslationGroup otherNode,
    required DiagnosticCollector diagnostics,
    required ExtraKeys extraKeys,
    required bool fillMissingFromBase,
  }) {
    final renamed = _renameIn(baseNode, otherNode);
    if (renamed != null) {
      diagnostics.add(
        _renameDiagnostic(
          base: base,
          other: other,
          from: renamed.from,
          to: renamed.to,
          // As severe as the pair it replaces: an extra key that a project
          // tolerates and a missing one it fills in are, together, still only
          // a warning.
          severe: !fillMissingFromBase || extraKeys == ExtraKeys.error,
        ),
      );
    }

    for (final baseChild in baseNode.children) {
      if (identical(baseChild, renamed?.to)) continue;
      final otherChild = otherNode.child(baseChild.key);
      if (otherChild == null) {
        // Name the file, not only the line: once `file_pattern` spreads a
        // locale over one file per feature, "line 4" alone names nothing.
        final source = baseChild.keySpan.sourceUrl;
        final where =
            'Base locale ${base.locale.toFileTag()} defines it at '
            '${source == null ? '' : '${p.basename(source.path)}:'}'
            '${baseChild.keySpan.start.line + 1}.';
        final covered = messageCount(baseChild);
        final scope = covered == 1 ? '' : ' It covers $covered messages.';
        diagnostics.add(
          fillMissingFromBase
              ? Diagnostic.warning(
                  code: 'missing_key',
                  message:
                      'Key "${baseChild.path}" is not translated in '
                      '${other.locale.toFileTag()}.',
                  span: otherNode.keySpan,
                  translationKey: baseChild.path,
                  details:
                      '$where$scope\n'
                      'It will render exactly as '
                      '${base.locale.toFileTag()} does.',
                )
              : Diagnostic.error(
                  code: 'missing_key',
                  message:
                      'Key "${baseChild.path}" is missing in '
                      '${other.locale.toFileTag()}.',
                  span: otherNode.keySpan,
                  translationKey: baseChild.path,
                  details:
                      '$where$scope\n'
                      'Add it, or set "fill_missing_from_base: true" to let '
                      'untranslated keys fall back.',
                ),
        );
        continue;
      }
      switch ((baseChild, otherChild)) {
        case (final TranslationGroup a, final TranslationGroup b):
          _compareStructure(
            fillMissingFromBase: fillMissingFromBase,
            extraKeys: extraKeys,
            base: base,
            other: other,
            baseNode: a,
            otherNode: b,
            diagnostics: diagnostics,
          );
        case (TranslationLeaf(), TranslationLeaf()):
          break;
        case (TranslationGroup(), TranslationLeaf()):
          diagnostics.add(
            Diagnostic.error(
              code: 'key_kind_mismatch',
              message:
                  '"${baseChild.path}" is a group in '
                  '${base.locale.toFileTag()} but a message here.',
              span: otherChild.keySpan,
              translationKey: baseChild.path,
            ),
          );
        case (TranslationLeaf(), TranslationGroup()):
          diagnostics.add(
            Diagnostic.error(
              code: 'key_kind_mismatch',
              message:
                  '"${baseChild.path}" is a message in '
                  '${base.locale.toFileTag()} but a group here.',
              span: otherChild.keySpan,
              translationKey: baseChild.path,
            ),
          );
      }
    }

    for (final otherChild in otherNode.children) {
      if (identical(otherChild, renamed?.from)) continue;
      if (baseNode.child(otherChild.key) != null) continue;
      // Reported on the group rather than on each key under it: a namespace
      // dropped from the base locale is one decision, and a hundred warnings
      // saying so is a report nobody reads. The count carries the size.
      final keys = _messageCount(otherChild);
      final scale = keys == 1 ? '' : ' ($keys keys)';
      diagnostics.add(switch (extraKeys) {
        ExtraKeys.error => Diagnostic.error(
          code: 'extra_key',
          message:
              'Key "${otherChild.path}" does not exist in the base locale '
              '${base.locale.toFileTag()}.$scale',
          span: otherChild.keySpan,
          translationKey: otherChild.path,
          details:
              'Add it to the base locale first, or remove it here. The base '
              'locale defines the generated API.\n'
              'Set "extra_keys: warn" to let a translation outlive the key '
              'it was written for.',
        ),
        ExtraKeys.warn => Diagnostic.warning(
          code: 'extra_key',
          message:
              'Key "${otherChild.path}" does not exist in the base locale '
              '${base.locale.toFileTag()}.$scale',
          span: otherChild.keySpan,
          translationKey: otherChild.path,
          details:
              'The translation is ignored: the base locale defines the '
              'generated API, so there is nothing for it to implement.\n'
              'Add the key to ${base.locale.toFileTag()}, or delete it '
              'here once the translators have caught up.',
        ),
      });
    }
  }

  /// How many messages [node] stands for: 1 for a leaf, the subtree's for a
  /// group.
  ///
  /// A diagnostic about an extra group names one key but covers everything
  /// under it, and "wallet is not in the base locale" reads very differently
  /// at 2 keys and at 200.
  static int _messageCount(TranslationNode node) => switch (node) {
    TranslationLeaf() => 1,
    TranslationGroup(:final children) => children.fold(
      0,
      (total, child) => total + _messageCount(child),
    ),
  };

  static void _compareSignature({
    required String key,
    required L10nLocale baseLocale,
    required MessageSignature baseSignature,
    required LocaleMessages other,
    required ParsedMessage message,
    required DiagnosticCollector diagnostics,
  }) {
    final collector = DiagnosticCollector();
    final signature = MessageSignature.infer(
      message.body,
      translationKey: key,
      diagnostics: collector,
    );
    diagnostics.addAll(collector.diagnostics);

    for (final entry in baseSignature.arguments.entries) {
      final expected = entry.value;
      final actual = signature.arguments[entry.key];
      if (actual == null) {
        diagnostics.add(
          Diagnostic.error(
            code: 'missing_placeholder',
            message: 'Argument "${entry.key}" is missing.',
            span: message.body.span,
            translationKey: key,
            details:
                'Base locale ${baseLocale.toFileTag()}:\n'
                '  argument: ${entry.key}\n'
                '  type: ${expected.kind.label}\n'
                '${other.locale.toFileTag()} locale:\n'
                '  argument is missing',
          ),
        );
        continue;
      }
      if (actual.kind.category != expected.kind.category) {
        diagnostics.add(
          Diagnostic.error(
            code: 'argument_kind_mismatch',
            message: 'Argument "${entry.key}" has a different type.',
            span: actual.span,
            translationKey: key,
            details:
                'Base locale ${baseLocale.toFileTag()}:\n'
                '  argument: ${entry.key}\n'
                '  type: ${expected.kind.label}\n'
                '${other.locale.toFileTag()} locale:\n'
                '  argument: ${entry.key}\n'
                '  type: ${actual.kind.label}',
          ),
        );
        continue;
      }
      if (actual.pluralType != expected.pluralType) {
        diagnostics.add(
          Diagnostic.error(
            code: 'plural_type_mismatch',
            message:
                'Argument "${entry.key}" is a '
                '${actual.pluralType?.label ?? 'plain number'} here but a '
                '${expected.pluralType?.label ?? 'plain number'} in the base '
                'locale.',
            span: actual.span,
            translationKey: key,
            details:
                'Cardinal and ordinal plurals select on different CLDR rules '
                'and mean different things: "3 items" versus "3rd".',
          ),
        );
        continue;
      }
      if (actual.format != expected.format) {
        diagnostics.add(
          Diagnostic.warning(
            code: 'format_style_mismatch',
            message:
                'Argument "${entry.key}" is formatted differently than in the '
                'base locale.',
            span: actual.span,
            translationKey: key,
            details:
                'Base locale ${baseLocale.toFileTag()}:\n'
                '  ${expected.format ?? 'no formatting'}\n'
                '${other.locale.toFileTag()} locale:\n'
                '  ${actual.format ?? 'no formatting'}\n'
                'The generated signature is the same, but the two locales will '
                'render the value differently.',
          ),
        );
      }
      if (expected.kind == ArgumentKind.select) {
        final expectedOptions = expected.selectOptions.toSet();
        final actualOptions = actual.selectOptions.toSet();
        if (!_setEquals(expectedOptions, actualOptions)) {
          final missing = expectedOptions.difference(actualOptions);
          final extra = actualOptions.difference(expectedOptions);
          diagnostics.add(
            Diagnostic.error(
              code: 'select_branch_mismatch',
              message:
                  'Select "${entry.key}" has different branches than the '
                  'base locale.',
              span: actual.span,
              translationKey: key,
              details:
                  'Base locale ${baseLocale.toFileTag()}:\n'
                  '  branches: ${_sorted(expectedOptions).join(', ')}\n'
                  '${other.locale.toFileTag()} locale:\n'
                  '  branches: ${_sorted(actualOptions).join(', ')}\n'
                  '${missing.isEmpty ? '' : '  missing: ${_sorted(missing).join(', ')}\n'}'
                  '${extra.isEmpty ? '' : '  unexpected: ${_sorted(extra).join(', ')}\n'}'
                  'Select branches become enum values, so every locale must '
                  'define exactly the same set.',
            ),
          );
        }
      }
    }

    for (final entry in signature.arguments.entries) {
      if (baseSignature.arguments.containsKey(entry.key)) continue;
      diagnostics.add(
        Diagnostic.error(
          code: 'extra_placeholder',
          message: 'Argument "${entry.key}" does not exist in the base locale.',
          span: entry.value.span,
          translationKey: key,
          details:
              'Base locale ${baseLocale.toFileTag()} declares: '
              '${baseSignature.arguments.keys.isEmpty ? '(none)' : baseSignature.arguments.keys.join(', ')}',
        ),
      );
    }
  }

  /// Whether the plural's `=N` branches already render all of [category].
  ///
  /// `gen_l10n` writes `{count, plural, =0{none} =1{one} other{# items}}`, and
  /// English `one` is true of 1 and of nothing else — so `=1` covers it and
  /// reporting `one` as missing is a warning with no fix, on every bundle
  /// imported from `gen_l10n`.
  ///
  /// Only a category CLDR defines as one exact value can be covered this way.
  /// Nothing tries to prove that a set of `=N` branches covers a range: `few`
  /// in Arabic is `n % 100 = 3..10`, which no list of literals closes, and a
  /// prover that got it wrong would silence a real warning.
  static bool _coveredByExactCases(
    PluralRuleSet rules,
    PluralNode plural,
    PluralCategory category,
  ) {
    // `offset:` puts the two sides on different numbers: ICU matches `=N`
    // against the original value and selects the category from the adjusted
    // one, so `=1` and `one` are not talking about the same input.
    if (plural.offset != 0) return false;

    final value = rules.exactValueOf(category);
    if (value == null) return false;
    return plural.cases.keys.any(
      (branch) => branch is ExactPluralCase && branch.value == value,
    );
  }

  static void _checkPluralCategories(
    LocaleMessages locale,
    ParsedMessage message,
    DiagnosticCollector diagnostics,
  ) {
    for (final plural in _pluralNodes(message.body)) {
      final rules = plural.type == PluralType.ordinal
          ? CldrPluralRules.ordinalForLanguage(locale.locale.language)
          : CldrPluralRules.forLanguage(locale.locale.language);
      if (rules == null) continue;
      final declared = plural.cases.keys
          .whereType<CategoryPluralCase>()
          .map((c) => c.category)
          .toSet();
      final supported = rules.categories;

      final missing = supported
          .difference(declared)
          .where((category) => !_coveredByExactCases(rules, plural, category))
          .toSet();
      if (missing.isNotEmpty) {
        diagnostics.add(
          Diagnostic.warning(
            code: 'missing_plural_category',
            message:
                'Plural "${plural.argument}" does not define '
                '${_sortedCategories(missing).join(', ')} for '
                '${locale.locale.toFileTag()}.',
            span: plural.span,
            translationKey: message.path,
            details:
                '${locale.locale.language} uses: '
                '${_sortedCategories(supported).join(', ')}.\n'
                'Those counts will fall back to the "other" branch.',
          ),
        );
      }

      final unused = declared.difference(supported);
      if (unused.isNotEmpty) {
        diagnostics.add(
          Diagnostic.warning(
            code: 'unused_plural_category',
            message:
                'Plural branch ${_sortedCategories(unused).join(', ')} can '
                'never match in ${locale.locale.toFileTag()}.',
            span: plural.span,
            translationKey: message.path,
            details:
                '${locale.locale.language} only uses: '
                '${_sortedCategories(supported).join(', ')}.',
          ),
        );
      }
    }
  }

  static List<PluralNode> _pluralNodes(MessageBody body) {
    final found = <PluralNode>[];
    void walk(MessageBody body) {
      for (final node in body.nodes) {
        switch (node) {
          case PluralNode():
            found.add(node);
            node.cases.values.forEach(walk);
          case SelectNode():
            node.cases.values.forEach(walk);
          case LiteralNode():
          case ArgumentNode():
          case NumberSignNode():
            break;
        }
      }
    }

    walk(body);
    return found;
  }

  static List<String> _sorted(Set<String> values) =>
      values.toList(growable: false)..sort();

  static List<String> _sortedCategories(Set<PluralCategory> values) =>
      (values.toList(growable: false)..sort((a, b) => a.index - b.index))
          .map((c) => c.name)
          .toList(growable: false);

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
