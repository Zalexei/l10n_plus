import 'package:source_span/source_span.dart';

import '../ast/rich_ast.dart';
import '../diagnostic.dart';

/// One locale's reading of a rich message.
final class RichLocaleMessage {
  /// Creates a locale's rich message.
  const RichLocaleMessage({
    required this.localeTag,
    required this.nodes,
    required this.span,
  });

  /// Locale file tag, e.g. `ru`.
  final String localeTag;

  /// The rich nodes parsed from this locale's string.
  final List<RichNode> nodes;

  /// Span of this locale's message, for the diagnostic.
  final SourceSpan span;
}

/// Checks that every locale of a rich message uses the same tags.
///
/// This is the strict half of the feature, and the reason is the generated
/// API rather than tidiness. The Flutter wrapper takes one builder per tag,
/// and the signature is shared by every locale — the base locale is the API
/// contract, exactly as it is for arguments and plural kinds. So a Russian
/// bundle that introduces `<bold>` asks for a builder the signature does not
/// have, and one that drops `<link>` leaves the application passing a builder
/// nothing will ever call. The first cannot be rendered at all; the second is
/// a translation that quietly lost its link.
///
/// Reported against the locale that differs, naming both files and lines:
/// which file to open is half the answer, and a span can only point at one of
/// them.
abstract final class RichTagValidator {
  /// Reports every locale of [messages] whose tag set differs from [base].
  static void validate({
    required String translationKey,
    required RichLocaleMessage base,
    required Iterable<RichLocaleMessage> messages,
    required DiagnosticCollector diagnostics,
  }) {
    final expected = richTagNames(base.nodes).toSet();
    for (final message in messages) {
      if (message.localeTag == base.localeTag) continue;
      final found = richTagNames(message.nodes).toSet();
      final missing = expected.difference(found);
      final unexpected = found.difference(expected);
      if (missing.isEmpty && unexpected.isEmpty) continue;

      diagnostics.add(
        Diagnostic.error(
          code: 'rich_tag_mismatch',
          message:
              'Rich message "$translationKey" uses different tags in '
              '${message.localeTag} than in the base locale.',
          span: message.span,
          translationKey: translationKey,
          details: [
            'Base locale ${base.localeTag} (${_at(base.span)}):',
            '  tags: ${_list(expected)}',
            '${message.localeTag} locale (${_at(message.span)}):',
            '  tags: ${_list(found)}',
            if (missing.isNotEmpty) '  missing: ${_list(missing)}',
            if (unexpected.isNotEmpty) '  unexpected: ${_list(unexpected)}',
            'Every locale must use the same tags: the generated wrapper takes '
                'one builder per tag of the base locale, so a tag only one '
                'locale writes has nothing to render it.',
          ].join('\n'),
        ),
      );
    }
  }

  /// `path:line:column` of [span].
  ///
  /// Written here rather than reused from `Diagnostic`, whose version is
  /// private and renders the span it is already printing. This one names the
  /// *other* file, which is the point of the details block.
  static String _at(SourceSpan span) {
    final start = span.start;
    final url = start.sourceUrl;
    final path = url == null
        ? '<unknown>'
        : (url.scheme.isEmpty || url.scheme == 'file'
              ? url.toFilePath()
              : url.toString());
    return '$path:${start.line + 1}:${start.column + 1}';
  }

  static String _list(Set<String> tags) {
    if (tags.isEmpty) return '(none)';
    return (tags.toList(
      growable: false,
    )..sort()).map((tag) => '<$tag>').join(', ');
  }
}
