import 'package:source_span/source_span.dart';

import '../ast/message_ast.dart';
import '../ast/rich_ast.dart';
import '../diagnostic.dart';

/// Result of reading the tags of one rich message.
final class RichParseResult {
  /// Creates a result.
  RichParseResult(this.nodes, this.diagnostics);

  /// The rich nodes, or `null` when the markup could not be read.
  final List<RichNode>? nodes;

  /// Problems found while reading.
  final List<Diagnostic> diagnostics;
}

/// Reads `<tag>…</tag>` out of an already parsed ICU message.
///
/// The input is the [MessageBody] the ICU parser produced, so quoting,
/// placeholders and formats are already resolved and a tag is found in the
/// literal text between them. Tags nest, and a tag may wrap placeholders and
/// further tags.
///
/// **What counts as markup.** A `<` begins a tag only when a tag name or `/`
/// follows it, which is what lets `3 < 4` and `<3` stay literal text in a
/// rich message. Once it does look like a tag it must *be* one: `<b` with no
/// `>` is reported rather than passed through, because the alternative is a
/// typo that renders as visible markup in a shipped app. A message that
/// genuinely needs a literal `<link>` is not a rich message, and the `(rich)`
/// suffix is what says which kind it is.
///
/// **A tag name is a word.** `[A-Za-z][A-Za-z0-9_]*`, which is exactly what
/// becomes a Dart parameter of the generated wrapper. Attributes (`<a
/// href="…">`) are deliberately not markup: a translation is text, and
/// anything a tag should carry is the application's to decide in the builder
/// it passes.
abstract final class RichMessageParser {
  /// `<tag>` or `</tag>`, anchored where a `<` was found.
  static final RegExp _tag = RegExp(r'<(/?)([A-Za-z][A-Za-z0-9_]*)>');

  /// Parses the tags of [body].
  static RichParseResult parse(
    MessageBody body, {
    required String translationKey,
  }) {
    final parser = _RichParser(translationKey);
    final nodes = parser._parse(body);
    return RichParseResult(nodes, parser._diagnostics);
  }
}

/// One run of the parser; holds the open tag stack and the diagnostics.
final class _RichParser {
  _RichParser(this.translationKey);

  /// Dotted key of the message being parsed, for diagnostics.
  final String translationKey;

  final List<Diagnostic> _diagnostics = [];
  final List<_Frame> _stack = [_Frame(null, null)];

  List<RichNode>? _parse(MessageBody body) {
    if (!_walk(body)) return null;
    final open = _stack.length > 1 ? _stack.last : null;
    if (open != null) {
      _error(
        code: 'rich_invalid_markup',
        message: 'Tag "<${open.tag}>" is never closed.',
        span: open.span ?? body.span,
        details:
            'Write </${open.tag}> where the region ends, or drop the opening '
            'tag.',
      );
      return null;
    }
    final root = _stack.single..flush();
    return root.children;
  }

  /// Walks [body], returning whether it was read without a fatal problem.
  bool _walk(MessageBody body) {
    for (final node in body.nodes) {
      switch (node) {
        case final LiteralNode literal:
          if (!_literal(literal)) return false;
        case ArgumentNode():
        case NumberSignNode():
          // Ordinary content: it joins the run of plain nodes being
          // collected, and the emitter interpolates it as it always has.
          _stack.last.pending.add(node);
        case LinkNode():
          // Why not: a link is resolved into the target's text, and a rich
          // message is not made of text — it is made of spans, with the tags
          // deciding where one span ends. Splicing a string into a run would
          // work; splicing one whose own words a translator might one day
          // want to wrap in a tag would not, and the difference is invisible
          // from here. Rather than support the half of it that happens to be
          // expressible, this says so.
          _error(
            code: 'rich_unsupported_link',
            message: 'A rich message cannot contain a link.',
            span: node.span,
            details:
                'Write the words here, or keep the shared text in a plain '
                'message and compose the two in Dart — a rich message '
                'already hands you its spans.\n'
                "To write the two characters literally, quote the at sign: "
                "'@':.",
          );
          return false;
        case PluralNode():
        case SelectNode():
          // Why a rich message may not be a plural or a select: the wrapper
          // the Flutter glue emits takes one builder per tag *the message
          // contains*, and that is what turns a forgotten tag into a compile
          // error. Inside branches the set of tags a call actually renders is
          // only known once the count or the enum value is, so the guarantee
          // would decay into "the builder you forgot is the branch you did
          // not test". Splitting the message says the same thing with the
          // types intact, so that is what the diagnostic asks for.
          _error(
            code: 'rich_unsupported_choice',
            message:
                'A rich message cannot contain a '
                '${node is PluralNode ? node.type.label : 'select'}.',
            span: node.span,
            details:
                'The generated wrapper requires one builder per tag in the '
                'message, which it can only do when the tags do not depend '
                'on a value chosen at run time.\n'
                'Write one rich message per branch and choose between them '
                'in Dart, or drop the "(rich)" suffix and keep the message '
                'plain text.',
          );
          return false;
      }
    }
    return true;
  }

  /// Reads the tags out of one literal, returning whether it was readable.
  bool _literal(LiteralNode literal) {
    final text = literal.value;
    var offset = 0;
    while (true) {
      final open = text.indexOf('<', offset);
      if (open < 0) {
        _text(literal, offset, text.length);
        return true;
      }
      _text(literal, offset, open);

      final match = RichMessageParser._tag.matchAsPrefix(text, open);
      if (match == null) {
        final next = open + 1 < text.length ? text[open + 1] : '';
        if (next != '/' && !_isLetter(next)) {
          // Not an attempt at a tag: keep the `<` as the text it is.
          _text(literal, open, open + 1);
          offset = open + 1;
          continue;
        }
        _error(
          code: 'rich_invalid_markup',
          message: 'Malformed tag in a rich message.',
          span: _fragment(literal, open, text.length),
          details:
              'A tag is written <name> or </name>, where the name starts '
              'with a letter and continues with letters, digits or "_".\n'
              'To keep a literal "<" in the text, write the message without '
              'the "(rich)" suffix.',
        );
        return false;
      }

      final name = match.group(2)!;
      final span = _fragment(literal, open, match.end);
      if (match.group(1) == '/') {
        if (!_close(name, span)) return false;
      } else {
        _stack.last.flush();
        _stack.add(_Frame(name, span));
      }
      offset = match.end;
    }
  }

  /// Closes [name], returning whether it was the tag that was actually open.
  bool _close(String name, SourceSpan span) {
    final frame = _stack.last;
    if (frame.tag == null) {
      _error(
        code: 'rich_invalid_markup',
        message: 'Closing tag "</$name>" has no opening tag.',
        span: span,
        details: 'Add <$name> where the region starts, or drop this tag.',
      );
      return false;
    }
    if (frame.tag != name) {
      // Crossed tags: `<b><i>x</b></i>`. Reported against the close that
      // cannot be honoured, naming the tag that is actually open — the two
      // together are the whole of what the author has to fix.
      _error(
        code: 'rich_invalid_markup',
        message: 'Tag "<${frame.tag}>" is closed by "</$name>".',
        span: span,
        details:
            'Tags nest, so the innermost open tag closes first.\n'
            '  open here: <${frame.tag}>\n'
            '  closed by: </$name>\n'
            'Write </${frame.tag}> first, or move the tags so that one '
            'contains the other.',
      );
      return false;
    }
    frame.flush();
    _stack.removeLast();
    _stack.last.children.add(
      RichTagNode(tag: name, children: frame.children, span: frame.span!),
    );
    return true;
  }

  /// Records `text[start..end)` as plain content of the open tag.
  void _text(LiteralNode literal, int start, int end) {
    if (end <= start) return;
    _stack.last.pending.add(
      LiteralNode(
        _fragment(literal, start, end),
        literal.value.substring(start, end),
      ),
    );
  }

  /// The span of `[start, end)` inside [literal].
  ///
  /// ICU quoting can make the literal's text shorter than the source it came
  /// from (`''` is one apostrophe), and a literal whose offsets were unknown
  /// carries the span of the whole string. In both cases the offsets no
  /// longer line up, so the whole literal is pointed at rather than the wrong
  /// few characters — the same rule the JSON parser follows for escapes.
  SourceSpan _fragment(LiteralNode literal, int start, int end) {
    final span = literal.span;
    if (span.length != literal.value.length) return span;
    return span.subspan(start, end);
  }

  void _error({
    required String code,
    required String message,
    required SourceSpan span,
    required String details,
  }) {
    _diagnostics.add(
      Diagnostic.error(
        code: code,
        message: message,
        span: span,
        translationKey: translationKey,
        details: details,
      ),
    );
  }

  static bool _isLetter(String char) =>
      char.length == 1 && RegExp('[A-Za-z]').hasMatch(char);
}

/// One open tag, collecting what it wraps.
final class _Frame {
  _Frame(this.tag, this.span);

  /// Tag name, or `null` for the message itself.
  final String? tag;

  /// Where the opening tag is, or `null` for the message itself.
  final SourceSpan? span;

  /// Finished nodes of this region, in order.
  final List<RichNode> children = [];

  /// Plain nodes seen since the last tag boundary.
  final List<MessageNode> pending = [];

  /// Turns the plain nodes collected so far into one text run.
  ///
  /// One run rather than one node each, so "Read the {name}" is a single
  /// `L10nTextSpan('Read the $name')` — the same string the plain emitter
  /// would have produced, and one span instead of two.
  void flush() {
    if (pending.isEmpty) return;
    children.add(
      RichTextNode(
        MessageBody(pending.toList(growable: false), pending.first.span),
      ),
    );
    pending.clear();
  }
}
