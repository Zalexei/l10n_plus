/// One piece of a rich message: either text, or a tag wrapping more pieces.
///
/// A rich message — a key written `terms(rich)` — generates a
/// `List<L10nSpan>` instead of a `String`, because the thing being
/// translated is no longer one run of characters: "Read the
/// `<link>`terms`</link>` to continue" is text, a named region, and text
/// again, and only the application knows what a link looks like.
///
/// This is deliberately *data*: no `TextSpan`, no `TextStyle`, nothing from
/// Flutter. The rule that keeps this package free of a Flutter dependency is
/// the same rule that makes a rich message readable from a server or a test,
/// and `l10n_plus_flutter` turns the data into an `InlineSpan` at the edge.
///
/// A message whose spans hold no placeholder is emitted as a `const` list, so
/// reading it allocates nothing — the same guarantee the plain string API
/// gives.
sealed class L10nSpan {
  /// Creates a span.
  const L10nSpan();

  /// The text of [spans] with every tag dropped.
  ///
  /// What the sentence says without any of its markup: the string to hand to
  /// a semantics label, a log line, or a test that does not care how the
  /// message is styled.
  static String plainText(Iterable<L10nSpan> spans) {
    final buffer = StringBuffer();
    void write(Iterable<L10nSpan> spans) {
      for (final span in spans) {
        switch (span) {
          case L10nTextSpan(:final text):
            buffer.write(text);
          case L10nTagSpan(:final children):
            write(children);
        }
      }
    }

    write(spans);
    return buffer.toString();
  }
}

/// Literal text, with every placeholder already interpolated.
final class L10nTextSpan extends L10nSpan {
  /// Creates a text span.
  const L10nTextSpan(this.text);

  /// The text to render.
  final String text;

  @override
  bool operator ==(Object other) => other is L10nTextSpan && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'L10nTextSpan($text)';
}

/// A named region of a message, holding the spans it wraps.
///
/// [tag] is the name as written in the translation (`<link>` is `link`), kept
/// as the translator typed it: the generated Flutter wrapper asks for one
/// builder per tag by name, and the name is the contract between the
/// translation file and the application.
final class L10nTagSpan extends L10nSpan {
  /// Creates a tag span.
  const L10nTagSpan(this.tag, this.children);

  /// Tag name, e.g. `link` or `bold`.
  final String tag;

  /// The spans this tag wraps. Tags nest, so these may be tags themselves.
  final List<L10nSpan> children;

  @override
  bool operator ==(Object other) =>
      other is L10nTagSpan &&
      other.tag == tag &&
      _listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(tag, Object.hashAll(children));

  @override
  String toString() => 'L10nTagSpan($tag, $children)';

  /// Element wise equality.
  ///
  /// Written out rather than imported: `package:collection` would be the
  /// first dependency of a package whose whole point is having none.
  static bool _listEquals(List<L10nSpan> a, List<L10nSpan> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
