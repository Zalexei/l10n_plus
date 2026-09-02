import 'package:l10n_plus/l10n_plus.dart';
import 'package:source_span/source_span.dart';

import '../ast/message_ast.dart';
import '../ast/message_metadata.dart';
import '../ast/translation_tree.dart';
import '../codegen/intl_formatters.dart';
import '../diagnostic.dart';
import 'source_parser.dart';
import 'span_json.dart';

/// Reads Application Resource Bundle files.
///
/// ARB is flat and JSON based, so this parser reuses [SpanJsonParser] and adds
/// the two things that make ARB different: document attributes (`@@locale`)
/// and per message metadata (`@key`).
///
/// Nesting is expressed by dots in the key: `auth.login.title` becomes
/// `t.auth.login.title`. Keys without dots stay at the top level, which is what
/// a bundle exported from `gen_l10n` or a TMS looks like.
final class ArbSourceParser implements TranslationSourceParser {
  /// Creates an ARB parser.
  const ArbSourceParser();

  /// Document attributes that are read rather than ignored.
  static const String _localeAttribute = '@@locale';

  /// Metadata attributes this parser understands. Anything else is ignored,
  /// because bundles routinely carry tool specific extras.
  static const Set<String> _knownMessageAttributes = {
    'description',
    'placeholders',
    'type',
    'context',
    'source_text',
    'screen',
  };

  @override
  Set<String> get extensions => const {'arb'};

  @override
  bool get declaresLocale => true;

  @override
  TranslationDocument? parse({
    required String content,
    required Uri uri,
    required L10nLocale? localeHint,
    required DiagnosticCollector diagnostics,
  }) {
    final JsonValue root;
    try {
      root = SpanJsonParser.parse(content, uri: uri);
    } on SpanJsonException catch (error) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_json',
          message: 'Could not parse ARB: ${error.message}.',
          span: error.span,
        ),
      );
      return null;
    }

    if (root is! JsonObject) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_root',
          message: 'An ARB file must contain a JSON object.',
          span: root.span,
        ),
      );
      return null;
    }

    final locale = _resolveLocale(root, uri, localeHint, diagnostics);
    if (locale == null) return null;

    final messages = <String, _RawMessage>{};
    final metadata = <String, JsonObject>{};
    final seen = <String, FileSpan>{};

    for (final member in root.entries) {
      final key = member.key;
      if (key.startsWith('@@')) continue; // Document attribute.

      final previous = seen[key];
      if (previous != null) {
        diagnostics.add(
          Diagnostic.error(
            code: 'duplicate_key',
            message: 'Duplicate key "$key".',
            span: member.keySpan,
            translationKey: key.startsWith('@') ? key.substring(1) : key,
            details:
                'First defined at line ${previous.start.line + 1}, '
                'column ${previous.start.column + 1}.',
          ),
        );
        continue;
      }
      seen[key] = member.keySpan;

      if (key.startsWith('@')) {
        final value = member.value;
        if (value is! JsonObject) {
          diagnostics.add(
            Diagnostic.error(
              code: 'invalid_metadata',
              message: 'Metadata "$key" must be an object.',
              span: value.span,
              translationKey: key.substring(1),
            ),
          );
          continue;
        }
        metadata[key.substring(1)] = value;
        continue;
      }

      final value = member.value;
      if (value is! JsonString) {
        diagnostics.add(
          Diagnostic.error(
            code: 'invalid_leaf_type',
            message: 'ARB message values must be strings.',
            span: value.span,
            translationKey: key,
            details:
                'ARB is a flat format. Nest keys by writing "a.b.c" rather '
                'than an object.',
          ),
        );
        continue;
      }
      if (key.isEmpty) {
        diagnostics.add(
          Diagnostic.error(
            code: 'empty_key',
            message: 'Translation keys must not be empty.',
            span: member.keySpan,
          ),
        );
        continue;
      }
      messages[key] = _RawMessage(member.keySpan, value);
    }

    for (final entry in metadata.entries) {
      if (messages.containsKey(entry.key)) continue;
      diagnostics.add(
        Diagnostic.error(
          code: 'orphan_metadata',
          message: 'Metadata "@${entry.key}" has no matching message.',
          span: entry.value.span,
          translationKey: entry.key,
          details:
              'Every "@key" block must sit next to a "key" message. Remove it '
              'or add the message.',
        ),
      );
    }

    return TranslationDocument(
      locale: locale,
      uri: uri,
      root: _buildTree(messages, metadata, root.span, diagnostics),
    );
  }

  /// ARB declares its own locale, and `@@locale` wins over the file name.
  ///
  /// That is what lets `app_en.arb`, the name `gen_l10n` uses, be read
  /// correctly even though `app_en` is itself a valid locale tag.
  L10nLocale? _resolveLocale(
    JsonObject root,
    Uri uri,
    L10nLocale? localeHint,
    DiagnosticCollector diagnostics,
  ) {
    for (final member in root.entries) {
      if (member.key != _localeAttribute) continue;
      final value = member.value;
      if (value is! JsonString) {
        diagnostics.add(
          Diagnostic.error(
            code: 'invalid_locale_attribute',
            message: '"$_localeAttribute" must be a string.',
            span: value.span,
          ),
        );
        return null;
      }
      final locale = L10nLocale.tryParse(value.value);
      if (locale == null) {
        diagnostics.add(
          Diagnostic.error(
            code: 'invalid_locale_attribute',
            message: '"${value.value}" is not a valid locale identifier.',
            span: value.span,
          ),
        );
        return null;
      }
      return locale;
    }

    if (localeHint == null) {
      diagnostics.add(
        Diagnostic.warning(
          code: 'unrecognized_file_name',
          message:
              'Skipping "${uri.pathSegments.last}": no "$_localeAttribute" '
              'attribute and the file name is not a locale.',
          details:
              'Add "$_localeAttribute": "en" to the bundle, or name the file '
              'after its locale.',
        ),
      );
    }
    return localeHint;
  }

  /// Expands dotted keys into the nested tree the rest of the pipeline uses.
  TranslationGroup _buildTree(
    Map<String, _RawMessage> messages,
    Map<String, JsonObject> metadata,
    FileSpan documentSpan,
    DiagnosticCollector diagnostics,
  ) {
    final root = _MutableGroup('', '', documentSpan);

    for (final entry in messages.entries) {
      final segments = entry.key.split('.');
      final raw = entry.value;

      if (segments.any((segment) => segment.isEmpty)) {
        diagnostics.add(
          Diagnostic.error(
            code: 'invalid_key',
            message: 'Key "${entry.key}" has an empty path segment.',
            span: raw.keySpan,
            translationKey: entry.key,
          ),
        );
        continue;
      }

      var group = root;
      var failed = false;
      for (final segment in segments.take(segments.length - 1)) {
        final existing = group.children[segment];
        if (existing is _MutableGroup) {
          group = existing;
          continue;
        }
        if (existing != null) {
          diagnostics.add(
            Diagnostic.error(
              code: 'key_kind_mismatch',
              message:
                  '"${entry.key}" needs "$segment" to be a group, but it is '
                  'already a message.',
              span: raw.keySpan,
              translationKey: entry.key,
            ),
          );
          failed = true;
          break;
        }
        final created = _MutableGroup(
          segment,
          group.path.isEmpty ? segment : '${group.path}.$segment',
          raw.keySpan,
        );
        group.children[segment] = created;
        group.order.add(segment);
        group = created;
      }
      if (failed) continue;

      final last = segments.last;
      if (group.children.containsKey(last)) {
        diagnostics.add(
          Diagnostic.error(
            code: 'key_kind_mismatch',
            message: '"${entry.key}" is already defined as a group.',
            span: raw.keySpan,
            translationKey: entry.key,
          ),
        );
        continue;
      }

      group.children[last] = TranslationLeaf(
        key: last,
        path: entry.key,
        keySpan: raw.keySpan,
        raw: raw.value.value,
        valueSpan: raw.value.span,
        contentOffset: raw.value.contentOffset,
        metadata: _metadataOf(entry.key, metadata[entry.key], diagnostics),
      );
      group.order.add(last);
    }

    return root.freeze();
  }

  MessageMetadata _metadataOf(
    String key,
    JsonObject? object,
    DiagnosticCollector diagnostics,
  ) {
    if (object == null) return MessageMetadata.empty;

    String? description;
    final placeholders = <String, PlaceholderMetadata>{};

    for (final member in object.entries) {
      if (!_knownMessageAttributes.contains(member.key)) {
        diagnostics.add(
          Diagnostic.warning(
            code: 'unknown_metadata_attribute',
            message: 'Ignoring unknown metadata attribute "${member.key}".',
            span: member.keySpan,
            translationKey: key,
          ),
        );
        continue;
      }
      switch (member.key) {
        case 'description':
          final value = member.value;
          if (value is JsonString) {
            description = value.value;
          } else {
            diagnostics.add(
              Diagnostic.warning(
                code: 'invalid_metadata',
                message: '"description" must be a string. Ignoring it.',
                span: value.span,
                translationKey: key,
              ),
            );
          }
        case 'placeholders':
          final value = member.value;
          if (value is! JsonObject) {
            diagnostics.add(
              Diagnostic.warning(
                code: 'invalid_metadata',
                message: '"placeholders" must be an object. Ignoring it.',
                span: value.span,
                translationKey: key,
              ),
            );
            continue;
          }
          for (final placeholder in value.entries) {
            final declaration = placeholder.value;
            if (declaration is! JsonObject) {
              diagnostics.add(
                Diagnostic.warning(
                  code: 'invalid_metadata',
                  message:
                      'Placeholder "${placeholder.key}" must be an object. '
                      'Ignoring it.',
                  span: declaration.span,
                  translationKey: key,
                ),
              );
              continue;
            }
            final currency = _currencyOptions(
              key,
              placeholder.key,
              declaration,
              diagnostics,
            );
            placeholders[placeholder.key] = PlaceholderMetadata(
              name: placeholder.key,
              span: placeholder.keySpan,
              type: _string(declaration, 'type'),
              format: _string(declaration, 'format'),
              example: _string(declaration, 'example'),
              description: _string(declaration, 'description'),
              currency: currency?.options,
              currencyCodeSpan: currency?.codeSpan,
              currencySpan: currency?.span,
            );
          }
        default:
          // Known but not acted on: `type`, `context`, `screen`, `source_text`.
          break;
      }
    }

    return MessageMetadata(
      description: description,
      placeholders: placeholders,
      span: object.span,
    );
  }

  /// Reads `optionalParameters`, the currency settings `gen_l10n` writes.
  ///
  /// `name`, `symbol` and `decimalDigits` are honoured. `customPattern` is
  /// reported rather than passed through: it is a raw ICU decimal pattern that
  /// `NumberFormat` only rejects when the app runs, and a build time generator
  /// that can produce a runtime throw is worse than one that says no.
  static _ParsedCurrency? _currencyOptions(
    String key,
    String placeholder,
    JsonObject declaration,
    DiagnosticCollector diagnostics,
  ) {
    final member = _member(declaration, 'optionalParameters');
    if (member == null) return null;
    final value = member.value;
    if (value is! JsonObject) {
      diagnostics.add(
        Diagnostic.warning(
          code: 'invalid_metadata',
          message: '"optionalParameters" must be an object. Ignoring it.',
          span: value.span,
          translationKey: key,
        ),
      );
      return null;
    }

    String? code;
    SourceSpan? codeSpan;
    String? symbol;
    int? decimalDigits;

    for (final parameter in value.entries) {
      final parameterValue = parameter.value;
      switch (parameter.key) {
        case 'name':
          if (parameterValue case final JsonString text) {
            code = text.value;
            codeSpan = text.span;
          } else {
            _invalidParameter(
              key,
              'name',
              'a string',
              parameterValue,
              diagnostics,
            );
          }
        case 'symbol':
          if (parameterValue case final JsonString text
              when text.value.isNotEmpty) {
            symbol = text.value;
          } else {
            _invalidParameter(
              key,
              'symbol',
              'a non empty string',
              parameterValue,
              diagnostics,
            );
          }
        case 'decimalDigits':
          final digits = _integer(parameterValue);
          if (digits == null || !IntlFormatters.isValidDecimalDigits(digits)) {
            _invalidParameter(
              key,
              'decimalDigits',
              'a whole number between 0 and '
                  '${IntlFormatters.maxDecimalDigits}',
              parameterValue,
              diagnostics,
            );
          } else {
            decimalDigits = digits;
          }
        default:
          diagnostics.add(
            Diagnostic.warning(
              code: 'unsupported_optional_parameter',
              message:
                  'Ignoring optional parameter "${parameter.key}" on '
                  'placeholder "$placeholder".',
              span: parameter.keySpan,
              translationKey: key,
              details:
                  'Supported: name, symbol, decimalDigits.\n'
                  'The value will be rendered with the locale default instead.',
            ),
          );
      }
    }

    final options = CurrencyOptions(
      code: code,
      symbol: symbol,
      decimalDigits: decimalDigits,
    );
    if (options.isEmpty) return null;
    return _ParsedCurrency(options, codeSpan, value.span);
  }

  static void _invalidParameter(
    String key,
    String name,
    String expected,
    JsonValue value,
    DiagnosticCollector diagnostics,
  ) {
    diagnostics.add(
      Diagnostic.warning(
        code: 'invalid_metadata',
        message: '"optionalParameters.$name" must be $expected. Ignoring it.',
        span: value.span,
        translationKey: key,
      ),
    );
  }

  /// Accepts `2` and `"2"`: hand written ARB uses both spellings.
  static int? _integer(JsonValue value) => switch (value) {
    final JsonNumber number when number.value is int => number.value as int,
    final JsonNumber number when number.value == number.value.roundToDouble() =>
      number.value.toInt(),
    final JsonString text => int.tryParse(text.value),
    _ => null,
  };

  static JsonMember? _member(JsonObject object, String key) {
    for (final member in object.entries) {
      if (member.key == key) return member;
    }
    return null;
  }

  static String? _string(JsonObject object, String key) {
    for (final member in object.entries) {
      if (member.key != key) continue;
      final value = member.value;
      return value is JsonString ? value.value : null;
    }
    return null;
  }
}

final class _RawMessage {
  _RawMessage(this.keySpan, this.value);

  final FileSpan keySpan;
  final JsonString value;
}

/// Tree node used while expanding dotted keys, before the immutable tree.
final class _MutableGroup {
  _MutableGroup(this.key, this.path, this.keySpan);

  final String key;
  final String path;
  final FileSpan keySpan;
  final Map<String, Object> children = {};
  final List<String> order = [];

  TranslationGroup freeze() {
    return TranslationGroup(
      key: key,
      path: path,
      keySpan: keySpan,
      children: [
        for (final name in order)
          switch (children[name]!) {
            final _MutableGroup group => group.freeze(),
            final TranslationLeaf leaf => leaf,
            _ => throw StateError('unreachable'),
          },
      ],
    );
  }
}

/// What `optionalParameters` held, with the spans diagnostics need.
final class _ParsedCurrency {
  const _ParsedCurrency(this.options, this.codeSpan, this.span);

  /// The settings themselves.
  final CurrencyOptions options;

  /// Span of the `name` value, or `null` when it was absent.
  final SourceSpan? codeSpan;

  /// Span of the whole `optionalParameters` object.
  final SourceSpan span;
}
