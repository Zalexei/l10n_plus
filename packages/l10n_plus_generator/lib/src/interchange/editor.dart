import 'dart:convert';

import '../ast/translation_tree.dart';
import 'catalog.dart';

/// One replacement in one file.
final class TextEdit {
  /// Creates an edit replacing `[start, end)` with [replacement].
  ///
  /// An insertion is the degenerate case where [start] and [end] are equal.
  const TextEdit({
    required this.start,
    required this.end,
    required this.replacement,
  });

  /// Offset of the first character replaced.
  final int start;

  /// Offset just past the last character replaced.
  final int end;

  /// What goes there instead.
  final String replacement;
}

/// Where a key that does not exist yet can be written, and at what indent.
final class InsertionPoint {
  /// Creates an insertion point.
  const InsertionPoint({
    required this.anchorPath,
    required this.offset,
    required this.indent,
    required this.step,
    required this.remaining,
    this.newline = '\n',
  });

  /// Dotted path of the existing group the new key is added to, `''` for the
  /// file's root. Identifies the point for grouping several additions.
  final String anchorPath;

  /// Offset the new text is spliced in at.
  final int offset;

  /// Column the first new entry starts at.
  final int indent;

  /// How much deeper each nested level is indented.
  final int step;

  /// Key segments that do not exist yet, relative to the anchor. Never empty.
  final List<String> remaining;

  /// The line ending the file already uses.
  ///
  /// A repository checked out on Windows has CRLF translation files, and
  /// adding one LF line to one of them turns the next diff into a file with
  /// mixed endings — a change nobody made and everybody has to review.
  final String newline;
}

/// Writing a value back into the file it came from.
///
/// `import` edits rather than rewrites. A translation file is a source file: it
/// has an order someone chose, blank lines between groups, comments in the
/// YAML case, and an indentation style. Reserializing the parsed tree would
/// produce a file that means the same and looks nothing like the one the
/// developer wrote, and the diff would be unreviewable — which is the same as
/// not being able to tell what the import did.
abstract final class TranslationEditor {
  /// The literal [format] spells [value] as.
  ///
  /// Round trips exactly: the text that comes back out of the parser for this
  /// literal is [value] again, whatever ICU syntax, quotes or braces are in
  /// it.
  static String encodeValue(TranslationFileFormat format, String value) =>
      switch (format) {
        // ARB is JSON, and `jsonEncode` is the one encoder nobody has to
        // review.
        TranslationFileFormat.json ||
        TranslationFileFormat.arb => jsonEncode(value),
        TranslationFileFormat.yaml => _encodeYaml(value),
      };

  /// A YAML scalar, single quoted unless single quoting cannot hold it.
  ///
  /// Single quoted is the right default for a translation: inside it a `{`, a
  /// `#` and a `:` are ordinary characters, so an ICU message needs no
  /// escaping beyond doubling its own quotes — and it is what hand written
  /// translation files already use. A message carrying a line break cannot be
  /// written that way without folding deciding what the break means, so those
  /// fall back to double quotes, where `\n` says it exactly.
  static String _encodeYaml(String value) {
    final needsEscapes = value.runes.any(
      (rune) => rune == 0x0a || rune == 0x0d || rune == 0x09 || rune < 0x20,
    );
    if (needsEscapes) {
      // YAML's double quoted style accepts every escape JSON produces.
      return jsonEncode(value);
    }
    return "'${value.replaceAll("'", "''")}'";
  }

  /// Replaces the text of [leaf] with [value].
  static TextEdit replace({
    required TranslationFileFormat format,
    required TranslationLeaf leaf,
    required String value,
  }) => TextEdit(
    start: leaf.valueSpan.start.offset,
    end: leaf.valueSpan.end.offset,
    replacement: encodeValue(format, value),
  );

  /// Where [segments] can be added to [file], or `null` when nowhere can.
  ///
  /// [segments] are relative to the file's own root, so a file matched by a
  /// `{namespace}` pattern has already had the namespace taken off.
  ///
  /// Returns `null` rather than guessing when the file has no content to
  /// anchor against, or when a segment is already a message. Producing a
  /// second `balance` next to an existing one would turn an import into a
  /// `duplicate_key` error in the next build, which is a worse outcome than a
  /// key the import says it could not place.
  static InsertionPoint? locate({
    required CatalogFile file,
    required List<String> segments,
  }) {
    if (segments.isEmpty) return null;
    final root = file.document.root;

    // ARB is flat: every key lives at the top level whatever its dots say, so
    // there is no group to walk into and the whole key is the new entry's
    // name. Its `@key` blocks sit between the messages, so the insertion goes
    // after the last message rather than after the last line.
    if (!file.format.isNested) {
      final leaves = leavesOf(root).toList(growable: false);
      if (leaves.isEmpty) return null;
      var offset = 0;
      var indent = 2;
      for (final leaf in leaves) {
        if (leaf.valueSpan.end.offset <= offset) continue;
        offset = leaf.valueSpan.end.offset;
        indent = leaf.keySpan.start.column;
      }
      return InsertionPoint(
        anchorPath: '',
        offset: offset,
        indent: indent,
        step: 2,
        remaining: [segments.join('.')],
        newline: _newlineOf(file.content),
      );
    }

    // Walk as deep as the file already goes, so a new key joins its siblings
    // rather than being bolted onto the root.
    final chain = <TranslationGroup>[root];
    var consumed = 0;
    for (final segment in segments) {
      final child = chain.last.child(segment);
      if (child is TranslationGroup) {
        chain.add(child);
        consumed++;
        continue;
      }
      // A message where a group is needed, or the last segment itself.
      if (child != null && consumed < segments.length - 1) return null;
      break;
    }
    if (consumed == segments.length) return null; // Already there.

    // An empty group has nothing to measure or anchor against, so the
    // insertion moves up to the nearest ancestor that has children and
    // recreates the rest of the path.
    while (chain.length > 1 && chain.last.children.isEmpty) {
      chain.removeLast();
      consumed--;
    }
    final anchor = chain.last;
    if (anchor.children.isEmpty) return null;

    final last = anchor.children.last;
    final offset = _endOfValue(file, last);
    if (offset == null) return null;

    final indent = last.keySpan.start.column;
    final depth = anchor.path.isEmpty ? 0 : anchor.path.split('.').length;
    final step = indent ~/ (depth + 1);

    return InsertionPoint(
      anchorPath: anchor.path,
      offset: offset,
      indent: indent,
      step: step <= 0 ? 2 : step,
      remaining: segments.sublist(consumed),
      newline: _newlineOf(file.content),
    );
  }

  /// Offset just past [node]'s value in [file].
  ///
  /// For a message that is the end of its literal. For a group it is the end
  /// of whatever closes it, which JSON spells with a brace the tree does not
  /// record and YAML spells with nothing at all.
  static int? _endOfValue(CatalogFile file, TranslationNode node) {
    switch (node) {
      case final TranslationLeaf leaf:
        return leaf.valueSpan.end.offset;
      case final TranslationGroup group:
        if (group.children.isEmpty) return null;
        final inner = _endOfValue(file, group.children.last);
        if (inner == null) return null;
        if (file.format == TranslationFileFormat.yaml) {
          // A block mapping ends where its last entry ends; the indentation
          // of what follows is what closes it.
          return inner;
        }
        var index = inner;
        while (index < file.content.length &&
            (file.content[index] == ' ' ||
                file.content[index] == '\t' ||
                file.content[index] == '\r' ||
                file.content[index] == '\n' ||
                file.content[index] == ',')) {
          index++;
        }
        if (index >= file.content.length || file.content[index] != '}') {
          return null;
        }
        return index + 1;
    }
  }

  /// Renders the text that adds [additions] at [point].
  ///
  /// [additions] maps the segments still to create onto the message text, and
  /// several additions sharing one anchor are rendered together: two new keys
  /// under the same new group have to produce one group, not two with the same
  /// name.
  static TextEdit insert({
    required TranslationFileFormat format,
    required InsertionPoint point,
    required List<({List<String> segments, String value})> additions,
  }) {
    final tree = _Node();
    for (final addition in additions) {
      var node = tree;
      for (final segment in addition.segments) {
        node = node.children.putIfAbsent(segment, _Node.new);
      }
      node.value = addition.value;
    }

    final buffer = StringBuffer();
    final entries = _render(
      format: format,
      node: tree,
      indent: point.indent,
      step: point.step,
      newline: point.newline,
    );
    // JSON separates entries with a comma; a YAML block mapping separates them
    // with nothing but the line they sit on.
    final lead = format == TranslationFileFormat.yaml ? '' : ',';
    for (final entry in entries) {
      buffer.write('$lead${point.newline}${' ' * point.indent}$entry');
    }

    return TextEdit(
      start: point.offset,
      end: point.offset,
      replacement: buffer.toString(),
    );
  }

  /// One rendered entry per child of [node], without its own indentation.
  static List<String> _render({
    required TranslationFileFormat format,
    required _Node node,
    required int indent,
    required int step,
    required String newline,
  }) {
    final rendered = <String>[];
    node.children.forEach((key, child) {
      final name = format == TranslationFileFormat.yaml
          ? _encodeYamlKey(key)
          : jsonEncode(key);
      if (child.children.isEmpty) {
        final value = encodeValue(format, child.value ?? '');
        rendered.add('$name: $value');
        return;
      }
      final inner = _render(
        format: format,
        node: child,
        indent: indent + step,
        step: step,
        newline: newline,
      );
      final pad = ' ' * (indent + step);
      switch (format) {
        case TranslationFileFormat.json:
        case TranslationFileFormat.arb:
          rendered.add(
            '$name: {$newline'
            '${inner.map((entry) => '$pad$entry').join(',$newline')}$newline'
            '${' ' * indent}}',
          );
        case TranslationFileFormat.yaml:
          rendered.add(
            '$name:$newline'
            '${inner.map((entry) => '$pad$entry').join(newline)}',
          );
      }
    });
    return rendered;
  }

  /// A YAML mapping key, quoted only when a bare word would not do.
  ///
  /// `true` and `null` are quoted along with the rest: YAML would read them as
  /// a boolean and a null, and a key that is not a string is an error in this
  /// generator's own YAML reader.
  static String _encodeYamlKey(String key) =>
      _plainKey.hasMatch(key) && !_implicitlyTyped.contains(key.toLowerCase())
      ? key
      : _encodeYaml(key);

  static final RegExp _plainKey = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');

  static const Set<String> _implicitlyTyped = {'true', 'false', 'null'};

  /// The line ending [content] already uses.
  ///
  /// The first break decides. A file with mixed endings is already somebody
  /// else's problem, and guessing a majority would not fix it.
  static String _newlineOf(String content) {
    final index = content.indexOf('\n');
    if (index > 0 && content[index - 1] == '\r') return '\r\n';
    return '\n';
  }

  /// Applies [edits] to [content].
  ///
  /// The edits must not overlap, and by construction they cannot: one message
  /// is replaced at its own literal, and an addition is spliced in after the
  /// value that precedes it. An overlap would mean a bug here rather than
  /// anything a user did, so it throws instead of writing a file that is the
  /// wrong half of two edits.
  static String apply(String content, List<TextEdit> edits) {
    final sorted = edits.toList()..sort((a, b) => a.start.compareTo(b.start));
    final buffer = StringBuffer();
    var cursor = 0;
    for (final edit in sorted) {
      if (edit.start < cursor) {
        throw ArgumentError.value(
          edit.start,
          'edits',
          'Overlapping edit; the previous one ended at $cursor',
        );
      }
      buffer
        ..write(content.substring(cursor, edit.start))
        ..write(edit.replacement);
      cursor = edit.end;
    }
    buffer.write(content.substring(cursor));
    return buffer.toString();
  }
}

/// A group of additions being built, before any text exists.
final class _Node {
  final Map<String, _Node> children = {};
  String? value;
}
