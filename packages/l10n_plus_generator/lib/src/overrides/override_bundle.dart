import 'package:l10n_plus/l10n_plus.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

import '../diagnostic.dart';
import '../source/span_json.dart';

/// One piece of override text the bundle states, and where it said it.
final class OverrideBundleText {
  /// Creates a text.
  OverrideBundleText({
    required this.branch,
    required this.nameSpan,
    required this.value,
    required this.valueSpan,
    required int? contentOffset,
    required SourceFile file,
  }) : _contentOffset = contentOffset,
       _file = file;

  /// The branch this text is for, or `null` for a message with one form.
  final String? branch;

  /// Where the branch — or the key, for a message with one form — is named.
  final SourceSpan nameSpan;

  /// The text as the bundle states it.
  final String value;

  /// The whole string literal.
  final SourceSpan valueSpan;

  final int? _contentOffset;
  final SourceFile _file;

  /// A span covering [length] characters of [value] from [offset].
  ///
  /// The same rule the translation parsers follow: point inside the string
  /// when the offsets line up, and fall back to the whole value when an escape
  /// sequence means they do not. A caret under the wrong character is worse
  /// than a caret under the whole string.
  SourceSpan spanAt(int offset, int length) {
    final start = _contentOffset;
    if (start == null) return valueSpan;
    final from = (start + offset).clamp(0, _file.length);
    final to = (start + offset + length).clamp(from, _file.length);
    return _file.span(from, to);
  }
}

/// One message the bundle overrides.
final class OverrideBundleMessage {
  /// Creates a message.
  OverrideBundleMessage({
    required this.key,
    required this.keySpan,
    required this.branched,
    required this.texts,
  });

  /// Dotted translation key.
  final String key;

  /// Where the key is named.
  final SourceSpan keySpan;

  /// Whether the bundle gave a map of branches rather than one text.
  final bool branched;

  /// The texts, in file order.
  final List<OverrideBundleText> texts;
}

/// A bundle of runtime overrides, as an application would install it.
///
/// Deliberately JSON and nothing else. ARB and CSV exist for translators, who
/// work on messages; this is a file an application downloads, and its shape is
/// the shape `L10nOverrides.install` takes — flat dotted keys, and either a
/// text or a map of branches.
///
/// Two entries are not messages: `@@locale`, which says which locale's plural
/// categories the branches are judged against, and `@@fingerprint`, which says
/// which build's messages they were judged against at all.
final class OverrideBundle {
  /// Creates a bundle.
  OverrideBundle({
    required this.path,
    required this.localeTag,
    required this.localeSpan,
    required this.messages,
    this.fingerprint,
    this.fingerprintSpan,
    this.rootSpan,
    this.firstMemberSpan,
  });

  /// The file this was read from, as the command line named it.
  ///
  /// Carried because one question about a bundle is about the others beside
  /// it: two files in a directory can be for one locale, and saying which two
  /// is the whole of that report.
  final String path;

  /// The locale the bundle is for, as a file tag.
  final String localeTag;

  /// Where the locale was stated, when it was stated in the file.
  final SourceSpan? localeSpan;

  /// Every message, in file order.
  final List<OverrideBundleMessage> messages;

  /// The overridable surface the bundle says it was checked against.
  ///
  /// `null` when the file states none, which is a bundle nothing checked.
  final String? fingerprint;

  /// Where [fingerprint] is stated, for the diagnostic and for `--stamp`.
  final SourceSpan? fingerprintSpan;

  /// The whole root object, for a diagnostic with nowhere better to point.
  final SourceSpan? rootSpan;

  /// Where the first member's key is, so `--stamp` can match its indentation.
  final SourceSpan? firstMemberSpan;

  /// The key an override bundle declares its locale with.
  ///
  /// `@@locale`, which is ARB's spelling. A bundle is handed to translators
  /// and tools that already know it, and inventing a second one would buy
  /// nothing.
  static const String localeKey = '@@locale';

  /// Reads [content] as an override bundle.
  ///
  /// [path] is only used to guess the locale when the file does not declare
  /// one: `overrides_en.json` and `en.json` both say `en`, which is what a
  /// per-locale download is usually called. A guess that cannot be made is an
  /// error rather than a default, because the locale decides which plural
  /// categories the branches are checked against.
  ///
  /// Returns `null` when nothing could be read at all.
  static OverrideBundle? read({
    required String content,
    required Uri uri,
    required String path,
    required DiagnosticCollector diagnostics,
  }) {
    final file = SourceFile.fromString(content, url: uri);

    final JsonValue root;
    try {
      root = SpanJsonParser.parse(content, uri: uri);
    } on SpanJsonException catch (error) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_override',
          message: 'Could not parse the override bundle: ${error.message}.',
          span: error.span,
        ),
      );
      return null;
    }

    if (root is! JsonObject) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_override',
          message: 'An override bundle must be a JSON object.',
          span: root.span,
          details:
              'One entry per message, keyed by its dotted translation key:\n'
              '  {\n'
              '    "$localeKey": "en",\n'
              '    "auth.login.title": "Sign in",\n'
              '    "wallet.transactions": {"one": "# payment", '
              '"other": "# payments"}\n'
              '  }',
        ),
      );
      return null;
    }

    String? localeTag;
    SourceSpan? localeSpan;
    String? fingerprint;
    SourceSpan? fingerprintSpan;
    final messages = <OverrideBundleMessage>[];

    for (final member in root.entries) {
      if (member.key == localeKey) {
        final value = member.value;
        localeSpan = value.span;
        if (value is! JsonString) {
          diagnostics.add(
            Diagnostic.error(
              code: 'unknown_override_locale',
              message: '"$localeKey" must be a locale tag such as "en".',
              span: value.span,
            ),
          );
          continue;
        }
        final locale = L10nLocale.tryParse(value.value);
        if (locale == null) {
          diagnostics.add(
            Diagnostic.error(
              code: 'unknown_override_locale',
              message: '"${value.value}" is not a locale identifier.',
              span: value.span,
              details: 'For example "en", "pt_BR" or "zh-Hant-TW".',
            ),
          );
          continue;
        }
        localeTag = locale.toFileTag();
        continue;
      }
      if (member.key == L10nOverrides.fingerprintKey) {
        final value = member.value;
        if (value is! JsonString) {
          diagnostics.add(
            Diagnostic.error(
              code: 'invalid_override',
              message:
                  '"${L10nOverrides.fingerprintKey}" must be the fingerprint '
                  'string "check-overrides --stamp" wrote.',
              span: value.span,
            ),
          );
          continue;
        }
        fingerprint = value.value;
        fingerprintSpan = value.span;
        continue;
      }
      if (member.key.startsWith('@')) {
        // ARB's per message metadata, which an override bundle has no use for
        // but a file round tripped through a tool may still carry.
        continue;
      }

      final value = member.value;
      if (value is JsonString) {
        messages.add(
          OverrideBundleMessage(
            key: member.key,
            keySpan: member.keySpan,
            branched: false,
            texts: [
              OverrideBundleText(
                branch: null,
                nameSpan: member.keySpan,
                value: value.value,
                valueSpan: value.span,
                contentOffset: value.contentOffset,
                file: file,
              ),
            ],
          ),
        );
        continue;
      }
      if (value is JsonObject) {
        final texts = <OverrideBundleText>[];
        for (final branch in value.entries) {
          final text = branch.value;
          if (text is! JsonString) {
            diagnostics.add(
              Diagnostic.error(
                code: 'invalid_override',
                message:
                    'Branch "${branch.key}" must be the text of that branch.',
                span: text.span,
                translationKey: member.key,
                details:
                    'A branch holds one string. A message that branches '
                    'twice — a select of plurals — states the nested branch '
                    'as one name, such as "0/one".',
              ),
            );
            continue;
          }
          texts.add(
            OverrideBundleText(
              branch: branch.key,
              nameSpan: branch.keySpan,
              value: text.value,
              valueSpan: text.span,
              contentOffset: text.contentOffset,
              file: file,
            ),
          );
        }
        messages.add(
          OverrideBundleMessage(
            key: member.key,
            keySpan: member.keySpan,
            branched: true,
            texts: texts,
          ),
        );
        continue;
      }

      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_override',
          message:
              'An override is a string, or a map of branch names to strings.',
          span: value.span,
          translationKey: member.key,
          details:
              'Found ${_describe(value)}. A message with one form takes its '
              'text; a plural or a select takes one text per branch.',
        ),
      );
    }

    localeTag ??= _localeFromPath(path);
    if (localeTag == null) {
      diagnostics.add(
        Diagnostic.error(
          code: 'unknown_override_locale',
          message: 'The bundle does not say which locale it is for.',
          span: root.span,
          details:
              'An override is checked against one locale\'s plural '
              'categories, so the locale cannot be guessed wrong.\n'
              'Declare it in the file:\n'
              '  "$localeKey": "en"\n'
              'or name the file after it, as in "overrides_en.json".',
        ),
      );
      return null;
    }

    return OverrideBundle(
      path: path,
      localeTag: localeTag,
      localeSpan: localeSpan,
      messages: messages,
      fingerprint: fingerprint,
      fingerprintSpan: fingerprintSpan,
      rootSpan: root.span,
      firstMemberSpan: root.entries.isEmpty ? null : root.entries.first.keySpan,
    );
  }

  /// The locale a file name states, or `null`.
  ///
  /// The whole base name first, so `en.json` works, then the part after the
  /// last separator, so `overrides_en.json` and `app-pt_BR.json` do too.
  static String? _localeFromPath(String path) {
    final name = p.basenameWithoutExtension(path);
    for (final candidate in [
      name,
      if (name.contains('_')) name.substring(name.lastIndexOf('_') + 1),
      if (name.contains('-')) name.substring(name.lastIndexOf('-') + 1),
      // `overrides_pt_BR` leaves `pt_BR` once the first segment is dropped.
      if (name.contains('_')) name.substring(name.indexOf('_') + 1),
    ]) {
      final locale = L10nLocale.tryParse(candidate);
      if (locale != null) return locale.toFileTag();
    }
    return null;
  }

  static String _describe(JsonValue value) => switch (value) {
    JsonNumber() => 'a number',
    JsonBoolean() => 'a boolean',
    JsonNull() => 'null',
    JsonArray() => 'a list',
    JsonObject() => 'an object',
    JsonString() => 'a string',
  };
}
