import 'package:l10n_plus/l10n_plus.dart';
import 'package:source_span/source_span.dart';

import '../rich/rich_key.dart';
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

/// What a group of leaves stands for.
///
/// A group is a namespace unless the source said otherwise, and the two ways
/// it can say so are deliberately the shapes a translator already writes: an
/// array, and `slang`'s `(map)` suffix on the key.
///
/// Both are still groups of ordinary leaves, which is the whole reason this is
/// a flag rather than a third kind of node. Each element is parsed as a
/// message, so placeholders, formats, plurals and links work inside one
/// without a line of new code; signature inference reads them; and the cross
/// locale check compares the element keys, so a list that is three long in
/// English and two in Russian is the missing key it already knows how to
/// report.
enum CollectionKind {
  /// A nested namespace, which is what a group is by default.
  namespace,

  /// A `List<String>`: the source value was an array, and the element keys
  /// are its indices.
  list,

  /// A `Map<String, String>`: the key carried the `(map)` suffix.
  map;

  /// Whether this is a collection rather than a namespace.
  bool get isCollection => this != CollectionKind.namespace;
}

/// The key suffix that makes a group a `Map<String, String>`.
///
/// The same argument [RichKey] makes, for the same reason: a group is a map
/// because its *key* says so and never because of what it contains. A project
/// with `{"errors": {"offline": "..."}}` has been generating a namespace from
/// that for as long as it has existed, and a library that started turning
/// every flat group into a map would silently change its API.
///
/// Written in every locale's file, like `(rich)`, so the existing cross locale
/// key check is what says a Russian bundle spelling it `countries` while
/// English spells it `countries(map)` has a missing key and an extra one.
///
/// The spelling is `slang`'s, deliberately: a team arriving from the main
/// competitor should be able to paste its translation files in. A list needs
/// no suffix because an array is already unambiguous.
abstract final class MapKey {
  /// The suffix, including the parentheses.
  static const String suffix = '(map)';

  /// Whether [key] marks a map.
  static bool isMap(String key) => key.endsWith(suffix);

  /// [key] without the suffix, which is what becomes the Dart identifier.
  static String baseName(String key) =>
      isMap(key) ? key.substring(0, key.length - suffix.length) : key;
}

/// An inner node: it becomes a nested namespace class in generated code.
final class TranslationGroup extends TranslationNode {
  /// Creates a group.
  TranslationGroup({
    required super.key,
    required super.path,
    required super.keySpan,
    required this.children,
    this.collection = CollectionKind.namespace,
  });

  /// Children in document order.
  final List<TranslationNode> children;

  /// Whether this group is a namespace, a list or a map.
  final CollectionKind collection;

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
