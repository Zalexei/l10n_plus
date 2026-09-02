import 'package:l10n_plus/l10n_plus.dart';
import 'package:path/path.dart' as p;

import '../ast/message_ast.dart';
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
            details:
                '${type.label} messages cannot be generated for this locale.\n'
                'Supported languages: '
                '${(type == PluralType.ordinal ? CldrPluralRules.supportedOrdinalLanguages : CldrPluralRules.supportedLanguages).join(', ')}.',
          ),
        );
        break;
      }
    }
  }

  static void _compareStructure({
    required LocaleMessages base,
    required LocaleMessages other,
    required TranslationGroup baseNode,
    required TranslationGroup otherNode,
    required DiagnosticCollector diagnostics,
    required bool fillMissingFromBase,
  }) {
    for (final baseChild in baseNode.children) {
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
      if (baseNode.child(otherChild.key) != null) continue;
      diagnostics.add(
        Diagnostic.error(
          code: 'extra_key',
          message:
              'Key "${otherChild.path}" does not exist in the base locale '
              '${base.locale.toFileTag()}.',
          span: otherChild.keySpan,
          translationKey: otherChild.path,
          details:
              'Add it to the base locale first, or remove it here. The base '
              'locale defines the generated API.',
        ),
      );
    }
  }

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

      final missing = supported.difference(declared);
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
