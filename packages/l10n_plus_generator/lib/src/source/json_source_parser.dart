import 'package:l10n_plus/l10n_plus.dart';
import 'package:source_span/source_span.dart';

import '../ast/translation_tree.dart';
import '../diagnostic.dart';
import 'source_parser.dart';
import 'span_json.dart';

/// Reads nested JSON translation files.
final class JsonSourceParser implements TranslationSourceParser {
  /// Creates a JSON parser.
  const JsonSourceParser();

  @override
  Set<String> get extensions => const {'json'};

  @override
  bool get declaresLocale => false;

  @override
  TranslationDocument? parse({
    required String content,
    required Uri uri,
    required L10nLocale? localeHint,
    required DiagnosticCollector diagnostics,
  }) {
    if (localeHint == null) {
      diagnostics.add(
        Diagnostic.warning(
          code: 'unrecognized_file_name',
          message:
              'Skipping "${uri.pathSegments.last}": JSON has nowhere to '
              'declare a locale, so the file name must be one.',
          details:
              'Name each file after its locale and nothing else, for example '
              '"en.json" or "pt_BR.json".',
        ),
      );
      return null;
    }

    final JsonValue root;
    try {
      root = SpanJsonParser.parse(content, uri: uri);
    } on SpanJsonException catch (error) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_json',
          message: 'Could not parse JSON: ${error.message}.',
          span: error.span,
        ),
      );
      return null;
    }

    if (root is! JsonObject) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_root',
          message: 'A translation file must contain a JSON object.',
          span: root.span,
        ),
      );
      return null;
    }

    final group = _group(
      object: root,
      key: '',
      path: '',
      keySpan: root.span,
      diagnostics: diagnostics,
    );
    return TranslationDocument(locale: localeHint, uri: uri, root: group);
  }

  TranslationGroup _group({
    required JsonObject object,
    required String key,
    required String path,
    required FileSpan keySpan,
    required DiagnosticCollector diagnostics,
  }) {
    final children = <TranslationNode>[];
    final seen = <String, FileSpan>{};

    for (final member in object.entries) {
      final previous = seen[member.key];
      if (previous != null) {
        diagnostics.add(
          Diagnostic.error(
            code: 'duplicate_key',
            message: 'Duplicate key "${member.key}".',
            span: member.keySpan,
            translationKey: _join(path, member.key),
            details:
                'First defined at line ${previous.start.line + 1}, '
                'column ${previous.start.column + 1}.',
          ),
        );
        continue;
      }
      seen[member.key] = member.keySpan;

      if (member.key.isEmpty) {
        diagnostics.add(
          Diagnostic.error(
            code: 'empty_key',
            message: 'Translation keys must not be empty.',
            span: member.keySpan,
          ),
        );
        continue;
      }

      final childPath = _join(path, member.key);
      final value = member.value;
      switch (value) {
        case JsonObject():
          children.add(
            _group(
              object: value,
              key: member.key,
              path: childPath,
              keySpan: member.keySpan,
              diagnostics: diagnostics,
            ),
          );
        case JsonString():
          children.add(
            TranslationLeaf(
              key: member.key,
              path: childPath,
              keySpan: member.keySpan,
              raw: value.value,
              valueSpan: value.span,
              contentOffset: value.contentOffset,
            ),
          );
        case JsonArray():
        case JsonNumber():
        case JsonBoolean():
        case JsonNull():
          diagnostics.add(
            Diagnostic.error(
              code: 'invalid_leaf_type',
              message: 'Translation values must be strings or objects.',
              span: value.span,
              translationKey: childPath,
              details:
                  'Found ${_describe(value)}. Wrap the value in quotes, or '
                  'use an object to nest more keys under "${member.key}".',
            ),
          );
      }
    }

    return TranslationGroup(
      key: key,
      path: path,
      keySpan: keySpan,
      children: children,
    );
  }

  static String _join(String path, String key) =>
      path.isEmpty ? key : '$path.$key';

  static String _describe(JsonValue value) => switch (value) {
    JsonArray() => 'an array',
    JsonNumber() => 'a number',
    JsonBoolean() => 'a boolean',
    JsonNull() => 'null',
    JsonObject() => 'an object',
    JsonString() => 'a string',
  };
}
