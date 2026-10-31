import 'package:source_span/source_span.dart';

import 'message_ast.dart';

/// A node of a rich message: a run of ordinary message content, or a tag.
///
/// This is a layer *over* the ICU AST rather than a part of it. A rich
/// message is parsed twice: once by the ICU parser, which resolves
/// quoting and placeholders and knows nothing about `<tag>`, and then by
/// `RichMessageParser`, which reads the tags out of the literals the first
/// pass produced.
///
/// Two consequences, both deliberate:
///
/// * every stage between the two — signature inference, cross locale
///   validation, the doc comment of the generated member — keeps seeing an
///   ordinary [MessageBody] in which `<link>` is literal text. A tag carries
///   no arguments and no branches, so there is nothing those stages would
///   decide differently, and none of them needed a new case;
/// * [MessageNode] stays closed over the five node kinds it had. Adding a
///   sixth would make every exhaustive switch over it incomplete, including
///   switches in files this layer has no business editing.
sealed class RichNode {
  const RichNode();
}

/// Ordinary message content: text and placeholders, no tags.
///
/// Holds a [MessageBody] rather than a string so the existing emitter renders
/// it: a run with a placeholder becomes an interpolation, a run with
/// `{amount, number, currency:USD}` in it becomes a formatter call, and the
/// rich path inherits all of it for free.
final class RichTextNode extends RichNode {
  /// Creates a text run.
  const RichTextNode(this.body);

  /// The plain content of this run.
  final MessageBody body;
}

/// A `<tag>…</tag>` region and the nodes it wraps.
final class RichTagNode extends RichNode {
  /// Creates a tag node.
  const RichTagNode({
    required this.tag,
    required this.children,
    required this.span,
  });

  /// Tag name as written, e.g. `link`.
  final String tag;

  /// What the tag wraps. Tags nest, so these may be tags themselves.
  final List<RichNode> children;

  /// Where the opening tag is, for diagnostics.
  final SourceSpan span;
}

/// Every tag name used in [nodes], at any depth, in document order.
///
/// Order is document order rather than alphabetical because it decides the
/// parameter order of the generated wrapper, and a parameter list that
/// reorders itself when a translator moves a tag would be a breaking change
/// nobody asked for.
List<String> richTagNames(List<RichNode> nodes) {
  final names = <String>{};
  void walk(List<RichNode> nodes) {
    for (final node in nodes) {
      if (node case final RichTagNode tag) {
        names.add(tag.tag);
        walk(tag.children);
      }
    }
  }

  walk(nodes);
  return names.toList(growable: false);
}

/// Where each tag of [nodes] was first opened, by tag name.
Map<String, SourceSpan> richTagSpans(List<RichNode> nodes) {
  final spans = <String, SourceSpan>{};
  void walk(List<RichNode> nodes) {
    for (final node in nodes) {
      if (node case final RichTagNode tag) {
        spans.putIfAbsent(tag.tag, () => tag.span);
        walk(tag.children);
      }
    }
  }

  walk(nodes);
  return spans;
}
