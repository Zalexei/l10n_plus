import 'package:l10n_plus/l10n_plus.dart';
import 'package:source_span/source_span.dart';

import 'message_ast.dart';
import 'message_metadata.dart';

/// A node of the translation key tree.
///
/// The tree is source format independent: JSON, ARB and YAML parsers all
/// produce this shape, and nothing downstream knows which one was used.
sealed class TranslationNode {
  TranslationNode({
    required this.key,
    required this.path,
    required this.keySpan,
  });

  /// The raw key as written in the source file, e.g. `login`.
  final String key;

  /// Full dotted path from the document root, e.g. `auth.login`.
  final String path;

  /// Span of the key in the source file.
  final FileSpan keySpan;
}

/// An inner node: it becomes a nested namespace class in generated code.
final class TranslationGroup extends TranslationNode {
  /// Creates a group.
  TranslationGroup({
    required super.key,
    required super.path,
    required super.keySpan,
    required this.children,
  });

  /// Children in document order.
  final List<TranslationNode> children;

  /// Child with [key], or `null`.
  TranslationNode? child(String key) {
    for (final child in children) {
      if (child.key == key) return child;
    }
    return null;
  }
}

/// Number of messages [node] stands for: 1 for a leaf, the whole subtree for
/// a group.
///
/// A diagnostic about a missing group names one key but covers everything
/// under it, and "wallet is untranslated" reads very differently at 2 keys
/// and at 200.
int messageCount(TranslationNode node) => switch (node) {
  TranslationLeaf() => 1,
  TranslationGroup(:final children) => children.fold(
    0,
    (total, child) => total + messageCount(child),
  ),
};

/// A leaf: one translatable message.
final class TranslationLeaf extends TranslationNode {
  /// Creates a leaf.
  TranslationLeaf({
    required super.key,
    required super.path,
    required super.keySpan,
    required this.raw,
    required this.valueSpan,
    required this.contentOffset,
    this.metadata = MessageMetadata.empty,
  });

  /// The message exactly as authored, before ICU parsing.
  final String raw;

  /// Span of the value literal, quotes included.
  final FileSpan valueSpan;

  /// File offset of the first character of [raw], or `null` when the literal
  /// used escape sequences and offsets no longer line up.
  final int? contentOffset;

  /// What the source format declared about this message.
  ///
  /// Empty for formats that cannot express it, such as plain JSON.
  final MessageMetadata metadata;
}

/// All translations of one locale, parsed from one source file.
final class TranslationDocument {
  /// Creates a document.
  TranslationDocument({
    required this.locale,
    required this.uri,
    required this.root,
  });

  /// The locale this file provides, derived from the file name.
  final L10nLocale locale;

  /// Where the document was read from.
  final Uri uri;

  /// Root group; its [TranslationNode.key] is empty.
  final TranslationGroup root;
}

/// A leaf whose message has been parsed into an ICU AST.
final class ParsedMessage {
  /// Creates a parsed message.
  ParsedMessage({required this.leaf, required this.body});

  /// The leaf this message came from.
  final TranslationLeaf leaf;

  /// Parsed ICU body.
  final MessageBody body;

  /// Dotted key path.
  String get path => leaf.path;
}
