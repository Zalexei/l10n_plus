import 'package:source_span/source_span.dart';

import 'message_ast.dart';

/// A placeholder declaration attached to a message by the source format.
///
/// ARB carries these under `@key.placeholders`. Plain JSON has no place to put
/// them, so they are absent there.
final class PlaceholderMetadata {
  /// Creates a declaration.
  const PlaceholderMetadata({
    required this.name,
    required this.span,
    this.type,
    this.format,
    this.example,
    this.description,
    this.currency,
    this.currencyCodeSpan,
    this.currencySpan,
  });

  /// Argument name the declaration applies to.
  final String name;

  /// Where the declaration is in the source file.
  final SourceSpan span;

  /// Declared type as written, e.g. `int` or `String`. `null` when omitted.
  final String? type;

  /// Declared format as written, e.g. `yMMMd` or `percent`.
  final String? format;

  /// Example value, carried through to the generated doc comment.
  final String? example;

  /// Prose description of the placeholder.
  final String? description;

  /// Currency settings, from ARB's `optionalParameters`.
  ///
  /// Those are the attributes `gen_l10n` reads, and they carry the names of
  /// the `NumberFormat.currency` parameters they end up in.
  final CurrencyOptions? currency;

  /// Where the currency code was declared, for diagnostics about it.
  final SourceSpan? currencyCodeSpan;

  /// Where `optionalParameters` was declared, for the other diagnostics.
  final SourceSpan? currencySpan;
}

/// Everything a source format knows about a message beyond its text.
final class MessageMetadata {
  /// Creates metadata.
  const MessageMetadata({
    this.description,
    this.placeholders = const {},
    this.span,
  });

  /// Metadata for a message the format carried no information about.
  static const MessageMetadata empty = MessageMetadata();

  /// Translator facing description, emitted as the member's doc comment.
  final String? description;

  /// Placeholder declarations keyed by argument name.
  final Map<String, PlaceholderMetadata> placeholders;

  /// Span of the metadata entry itself, for diagnostics about it.
  final SourceSpan? span;

  /// Whether anything was declared at all.
  bool get isEmpty => description == null && placeholders.isEmpty;
}
