import 'package:flutter/widgets.dart';
import 'package:l10n_plus/l10n_plus.dart';

/// Wraps the children of one tag of a rich message.
///
/// The application decides what `<link>` or `<bold>` means — a style, a
/// gesture recognizer, a `WidgetSpan` with an icon in it — so the library
/// asks for a function and renders what it returns. [children] are the spans
/// the tag wraps, already folded, which is what makes tags nest.
typedef L10nSpanBuilder = InlineSpan Function(List<InlineSpan> children);

/// Folds the [spans] of a rich message into one [TextSpan].
///
/// [tags] must hold a builder for every tag the message contains. Generated
/// code satisfies that by construction: the wrapper emitted for a rich
/// message takes one required builder per tag found in the translation, so a
/// forgotten tag is a compile error. This function is the same thing for a
/// call written by hand, and it has no compiler to lean on — so a tag with no
/// builder throws rather than rendering its text unstyled, which is the kind
/// of silent wrongness this library exists to make impossible.
TextSpan l10nTextSpan(
  List<L10nSpan> spans, {
  required Map<String, L10nSpanBuilder> tags,
  TextStyle? style,
}) => TextSpan(style: style, children: _fold(spans, tags));

List<InlineSpan> _fold(
  List<L10nSpan> spans,
  Map<String, L10nSpanBuilder> tags,
) {
  final children = <InlineSpan>[];
  for (final span in spans) {
    switch (span) {
      case L10nTextSpan(:final text):
        children.add(TextSpan(text: text));
      case L10nTagSpan(:final tag, children: final wrapped):
        final builder = tags[tag];
        if (builder == null) {
          throw ArgumentError.value(
            tag,
            'tags',
            'No builder for tag "<$tag>". Builders given: '
                '${tags.keys.isEmpty ? '(none)' : tags.keys.join(', ')}',
          );
        }
        children.add(builder(_fold(wrapped, tags)));
    }
  }
  return children;
}
