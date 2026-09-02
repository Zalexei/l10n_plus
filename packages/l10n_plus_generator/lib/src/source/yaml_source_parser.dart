import 'package:l10n_plus/l10n_plus.dart';
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import '../ast/translation_tree.dart';
import '../diagnostic.dart';
import 'source_parser.dart';

/// Reads nested YAML translation files.
///
/// `package:yaml` is already a dependency and is span aware, so this parser
/// has no hand written scanner behind it the way JSON does — the work is
/// mapping YAML's node types onto the translation tree and being careful about
/// two things YAML does that JSON does not.
///
/// The first is implicit typing. `package:yaml` implements YAML 1.2, so the
/// old `yes`/`no`/`on`/`off` booleans really are strings — but `true`,
/// `false`, `null`, `~`, `5` and `.inf` are not, and a translation that reads
/// as any of them silently stops being text. That gets a diagnostic naming
/// what it became and how to keep it, rather than the generic "values must be
/// strings".
///
/// The second is scalar styles. A plain scalar's span covers exactly its
/// content, a quoted one includes the quotes, and a block scalar includes its
/// indicator. Since ICU diagnostics point *inside* the message, the content
/// offset is computed only where it is provably right, and left null
/// otherwise — the same rule the JSON parser uses for escapes.
final class YamlSourceParser implements TranslationSourceParser {
  /// Creates a YAML parser.
  const YamlSourceParser();

  @override
  Set<String> get extensions => const {'yaml', 'yml'};

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
              'Skipping "${uri.pathSegments.last}": YAML has nowhere to '
              'declare a locale, so the path must say which it is.',
          details:
              'Name each file after its locale, for example "en.yaml", or '
              'set "file_pattern".',
        ),
      );
      return null;
    }

    final file = SourceFile.fromString(content, url: uri);

    final YamlNode root;
    try {
      root = loadYamlNode(content, sourceUrl: uri);
    } on YamlException catch (error) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_yaml',
          message: 'Could not parse YAML: ${error.message}.',
          span: error.span ?? file.span(0, 0),
          details: _yamlHint(error),
        ),
      );
      return null;
    }

    if (root is! YamlMap) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_root',
          message: 'A translation file must contain a YAML map.',
          span: _span(file, root.span),
        ),
      );
      return null;
    }

    return TranslationDocument(
      locale: localeHint,
      uri: uri,
      root: _group(
        map: root,
        key: '',
        path: '',
        keySpan: _span(file, root.span),
        file: file,
        content: content,
        diagnostics: diagnostics,
      ),
    );
  }

  TranslationGroup _group({
    required YamlMap map,
    required String key,
    required String path,
    required FileSpan keySpan,
    required SourceFile file,
    required String content,
    required DiagnosticCollector diagnostics,
  }) {
    final children = <TranslationNode>[];

    for (final entry in map.nodes.entries) {
      final keyNode = entry.key as YamlNode;
      final childKeySpan = _span(file, keyNode.span);
      final name = keyNode is YamlScalar ? keyNode.value : null;

      if (name is! String) {
        // `1: hello` is a valid YAML map with an integer key.
        diagnostics.add(
          Diagnostic.error(
            code: 'invalid_key',
            message: 'Translation keys must be strings.',
            span: childKeySpan,
            translationKey: path,
            details:
                'Found ${_describe(keyNode)}. Quote it to keep it a key: '
                '"$name".',
          ),
        );
        continue;
      }
      if (name.isEmpty) {
        diagnostics.add(
          Diagnostic.error(
            code: 'empty_key',
            message: 'Translation keys must not be empty.',
            span: childKeySpan,
          ),
        );
        continue;
      }

      // `package:yaml` reports duplicate keys itself, as a parse error, so a
      // map that got this far cannot have any.
      final childPath = path.isEmpty ? name : '$path.$name';
      final value = entry.value;

      if (value is YamlMap) {
        children.add(
          _group(
            map: value,
            key: name,
            path: childPath,
            keySpan: childKeySpan,
            file: file,
            content: content,
            diagnostics: diagnostics,
          ),
        );
        continue;
      }

      if (value is YamlScalar && value.value is String) {
        final valueSpan = _span(file, value.span);
        children.add(
          TranslationLeaf(
            key: name,
            path: childPath,
            keySpan: childKeySpan,
            raw: value.value as String,
            valueSpan: valueSpan,
            contentOffset: _contentOffset(
              content: content,
              span: valueSpan,
              value: value.value as String,
            ),
          ),
        );
        continue;
      }

      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_leaf_type',
          message: 'Translation values must be strings or maps.',
          span: _span(file, value.span),
          translationKey: childPath,
          details: _leafHelp(value),
        ),
      );
    }

    return TranslationGroup(
      key: key,
      path: path,
      keySpan: keySpan,
      children: children,
    );
  }

  /// Where the message's first character is, or `null` when it cannot be said.
  ///
  /// Only plain and simply quoted scalars are resolved. Anything with escapes,
  /// folding or line continuations no longer maps character for character onto
  /// the source, and a wrong offset would point ICU diagnostics at the wrong
  /// place — worse than pointing at the whole value.
  static int? _contentOffset({
    required String content,
    required FileSpan span,
    required String value,
  }) {
    final start = span.start.offset;
    final text = content.substring(start, span.end.offset);
    if (text == value) return start;
    for (final quote in const ["'", '"']) {
      if (text == '$quote$value$quote') return start + 1;
    }
    return null;
  }

  /// A `FileSpan` over our own [file], from any span `package:yaml` produced.
  ///
  /// Going through offsets rather than casting keeps this independent of what
  /// `package:yaml` happens to return.
  static FileSpan _span(SourceFile file, SourceSpan span) {
    final start = span.start.offset.clamp(0, file.length);
    final end = span.end.offset.clamp(start, file.length);
    return file.span(start, end);
  }

  static String _leafHelp(YamlNode value) {
    if (value is YamlScalar) {
      // The YAML footgun. `yes` and `no` survive — YAML 1.2 dropped them — but
      // `true`, `null`, `~` and anything numeric do not, so a translation
      // quietly stops being text.
      return 'Found ${_describe(value)}. YAML reads bare words such as "true", '
          '"false", "null" and "~", and anything numeric, as values rather '
          'than text — quote it to keep it a translation.';
    }
    return 'Found ${_describe(value)}. Quote the value, or use a map to nest '
        'more keys under it.';
  }

  static String _describe(YamlNode node) {
    if (node is YamlList) return 'a list';
    if (node is YamlMap) return 'a map';
    final value = node is YamlScalar ? node.value : null;
    return switch (value) {
      String() => 'a string',
      bool() => 'a boolean',
      int() => 'an integer',
      double() => 'a number',
      null => 'null',
      _ => 'a ${value.runtimeType}',
    };
  }
}

/// What a raw `package:yaml` error usually means in a translation file.
///
/// Nearly every ICU message starts with `{`, which YAML reads as the opening
/// of a flow mapping — so the first YAML file anyone writes fails with
/// "Expected a key while parsing a block mapping", which is true and does not
/// mention translations, braces or quoting.
String? _yamlHint(YamlException error) {
  final message = error.message.toLowerCase();
  if (!message.contains('block mapping') && !message.contains('flow mapping')) {
    return null;
  }
  return 'A message starting with `{` must be quoted: YAML reads a bare `{` '
      'as the start of a flow mapping.\n'
      "  greeting: '{name}, hello'";
}
