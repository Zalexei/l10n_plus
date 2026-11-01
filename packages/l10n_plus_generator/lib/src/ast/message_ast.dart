import 'package:source_span/source_span.dart';

/// A CLDR plural category.
enum PluralCategory {
  /// `zero`
  zero,

  /// `one`
  one,

  /// `two`
  two,

  /// `few`
  few,

  /// `many`
  many,

  /// `other`, the required catch-all branch.
  other;

  /// Parses a category name, or returns `null`.
  static PluralCategory? tryParse(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// A branch selector of a `plural` argument.
sealed class PluralCase implements Comparable<PluralCase> {
  const PluralCase();

  /// Selector as written, e.g. `=0` or `one`.
  String get label;

  @override
  int compareTo(PluralCase other) => switch ((this, other)) {
    (final ExactPluralCase a, final ExactPluralCase b) => a.value.compareTo(
      b.value,
    ),
    (ExactPluralCase(), CategoryPluralCase()) => -1,
    (CategoryPluralCase(), ExactPluralCase()) => 1,
    (final CategoryPluralCase a, final CategoryPluralCase b) =>
      a.category.index.compareTo(b.category.index),
  };
}

/// An `=N` literal match, checked before category rules.
final class ExactPluralCase extends PluralCase {
  /// Creates an exact match on [value].
  const ExactPluralCase(this.value);

  /// The literal number to match.
  final num value;

  @override
  String get label => '=$value';

  @override
  bool operator ==(Object other) =>
      other is ExactPluralCase && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => label;
}

/// A CLDR category match such as `one` or `other`.
final class CategoryPluralCase extends PluralCase {
  /// Creates a category match.
  const CategoryPluralCase(this.category);

  /// The matched category.
  final PluralCategory category;

  @override
  String get label => category.name;

  @override
  bool operator ==(Object other) =>
      other is CategoryPluralCase && other.category == category;

  @override
  int get hashCode => category.hashCode;

  @override
  String toString() => label;
}

/// What an `{arg, number|date|time}` argument formats.
enum ArgumentFormatKind {
  /// `{n, number}`
  number,

  /// `{d, date}`
  date,

  /// `{t, time}`
  time;

  /// Name as written in ICU.
  String get label => name;
}

/// How a currency amount is rendered, beyond the locale's own defaults.
///
/// The three settings always travel together and only ever apply to the
/// `currency` and `simpleCurrency` styles, so they are one value rather than
/// three fields on every [ArgumentFormat]. Each maps onto the `NumberFormat`
/// constructor parameter of the same meaning.
final class CurrencyOptions {
  /// Creates currency options.
  const CurrencyOptions({this.code, this.symbol, this.decimalDigits});

  /// ISO 4217 code, e.g. `USD`. `NumberFormat`'s `name:`.
  ///
  /// `null` means the currency of the locale being rendered.
  final String? code;

  /// Literal symbol to print instead of the one the style would choose.
  final String? symbol;

  /// Digits after the decimal separator, overriding the currency default.
  final int? decimalDigits;

  /// Whether nothing at all was specified.
  bool get isEmpty => code == null && symbol == null && decimalDigits == null;

  /// This value with any field of [other] that is set here left alone.
  CurrencyOptions merge(CurrencyOptions other) => CurrencyOptions(
    code: code ?? other.code,
    symbol: symbol ?? other.symbol,
    decimalDigits: decimalDigits ?? other.decimalDigits,
  );

  @override
  bool operator ==(Object other) =>
      other is CurrencyOptions &&
      other.code == code &&
      other.symbol == symbol &&
      other.decimalDigits == decimalDigits;

  @override
  int get hashCode => Object.hash(code, symbol, decimalDigits);

  @override
  String toString() {
    final parts = [
      if (code != null) code!,
      if (symbol != null) 'symbol $symbol',
      if (decimalDigits != null) '$decimalDigits digits',
    ];
    return parts.join(', ');
  }
}

/// The formatting requested by an argument.
final class ArgumentFormat {
  /// Creates a format.
  const ArgumentFormat(this.kind, [this.style, this.currency]);

  /// Whether a number, a date or a time is formatted.
  final ArgumentFormatKind kind;

  /// Style as written, e.g. `percent` or the date skeleton `yMMMd`.
  ///
  /// `null` means the format's default style.
  final String? style;

  /// Currency settings, for the `currency` and `simpleCurrency` styles.
  final CurrencyOptions? currency;

  @override
  bool operator ==(Object other) =>
      other is ArgumentFormat &&
      other.kind == kind &&
      other.style == style &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(kind, style, currency);

  @override
  String toString() {
    if (style == null) return kind.label;
    final options = currency;
    final suffix = options == null || options.isEmpty ? '' : ':$options';
    return '${kind.label}, $style$suffix';
  }
}

/// A node of a parsed ICU message.
sealed class MessageNode {
  MessageNode(this.span);

  /// Where this node is in the source file.
  final SourceSpan span;
}

/// Literal text.
final class LiteralNode extends MessageNode {
  /// Creates a literal.
  LiteralNode(super.span, this.value);

  /// The text, with ICU quoting already resolved.
  final String value;
}

/// A `{name}` placeholder, optionally formatted as `{name, number}` and
/// friends.
final class ArgumentNode extends MessageNode {
  /// Creates a placeholder reference.
  ArgumentNode(super.span, this.name, {this.format});

  /// Argument name.
  final String name;

  /// Requested formatting, or `null` for a plain string substitution.
  final ArgumentFormat? format;
}

/// The `#` shorthand inside a plural branch, standing for the plural argument.
final class NumberSignNode extends MessageNode {
  /// Creates a `#` reference to [argument].
  NumberSignNode(super.span, this.argument);

  /// The enclosing plural argument's name.
  final String argument;
}

/// A `@:other.key` reference to the text of another message.
///
/// Resolved by the generator, never at run time: by the time the emitter sees
/// one it knows the target's text in this locale and the target's parameters,
/// so a link becomes either the target's literal text written in place or a
/// call to the target's accessor. Nothing about a link survives into the
/// generated code as a link.
final class LinkNode extends MessageNode {
  /// Creates a reference to [path].
  LinkNode(super.span, this.path);

  /// Dotted key of the message whose text goes here.
  ///
  /// Absolute, and checked against the project: a path nothing defines is an
  /// error with the nearest key offered, and a path that leads back here is a
  /// cycle named in full.
  final String path;
}

/// Whether a choice selects on cardinal or ordinal plural rules.
enum PluralType {
  /// `{n, plural, ...}`: one item, two items.
  cardinal,

  /// `{n, selectordinal, ...}`: 1st, 2nd, 3rd.
  ordinal;

  /// Name as written in ICU.
  String get label => this == PluralType.cardinal ? 'plural' : 'selectordinal';
}

/// A `{arg, plural, ...}` or `{arg, selectordinal, ...}` argument.
final class PluralNode extends MessageNode {
  /// Creates a plural argument.
  PluralNode(
    super.span,
    this.argument,
    this.cases, {
    this.type = PluralType.cardinal,
    this.offset = 0,
  });

  /// Argument name.
  final String argument;

  /// Branches in document order. Always contains [PluralCategory.other].
  final Map<PluralCase, MessageBody> cases;

  /// Which CLDR rule table selects the branch.
  final PluralType type;

  /// Value subtracted before category selection and before rendering `#`.
  ///
  /// `offset:1` turns "you and 2 others" into a message where `#` shows 2 for
  /// an input of 3. Explicit `=N` branches still match the original value, as
  /// ICU specifies.
  final num offset;
}

/// A `{arg, select, ...}` argument.
final class SelectNode extends MessageNode {
  /// Creates a select argument.
  SelectNode(super.span, this.argument, this.cases);

  /// Argument name.
  final String argument;

  /// Branches in document order. Always contains `other`.
  final Map<String, MessageBody> cases;
}

/// A sequence of message nodes: a whole message, or one branch of it.
final class MessageBody {
  /// Creates a body.
  MessageBody(this.nodes, this.span);

  /// Child nodes in order.
  final List<MessageNode> nodes;

  /// Span covering the whole body.
  final SourceSpan span;

  /// Whether the body is a single plural or select argument and nothing else.
  ///
  /// Such messages can be emitted as plain statements instead of needing a
  /// private helper method.
  bool get isSingleChoice =>
      nodes.length == 1 &&
      (nodes.single is PluralNode || nodes.single is SelectNode);
}
