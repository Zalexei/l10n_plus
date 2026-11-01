import 'package:source_span/source_span.dart';

import '../ast/message_ast.dart';
import '../diagnostic.dart';

/// The family of Dart type an argument produces.
///
/// Conflicts are decided on this rather than on [ArgumentKind], because
/// `{d, date}` and `{d, time}` legitimately refer to one `DateTime` argument.
enum ArgumentTypeCategory {
  /// `String`.
  text,

  /// `num` and its subtypes.
  number,

  /// `DateTime`.
  dateTime,

  /// A generated select enum.
  enumeration,
}

/// What kind of Dart parameter an ICU argument turns into.
enum ArgumentKind {
  /// A `{name}` placeholder, generated as `String`.
  plain(ArgumentTypeCategory.text, 'placeholder'),

  /// A `{n, number}` argument, generated as `num`.
  number(ArgumentTypeCategory.number, 'number'),

  /// A `{d, date}` argument, generated as `DateTime`.
  date(ArgumentTypeCategory.dateTime, 'date'),

  /// A `{t, time}` argument, generated as `DateTime`.
  time(ArgumentTypeCategory.dateTime, 'time'),

  /// A plural argument, generated as `num`.
  plural(ArgumentTypeCategory.number, 'plural'),

  /// A select argument, generated as a dedicated enum.
  select(ArgumentTypeCategory.enumeration, 'select');

  const ArgumentKind(this.category, this.label);

  /// The Dart type family this kind produces.
  final ArgumentTypeCategory category;

  /// Human readable name used in diagnostics.
  final String label;

  /// How strongly this kind determines the generated signature.
  ///
  /// A plain reference inside a plural branch must not override the plural.
  int get precedence => switch (this) {
    ArgumentKind.plain => 0,
    ArgumentKind.number || ArgumentKind.date || ArgumentKind.time => 1,
    ArgumentKind.plural || ArgumentKind.select => 2,
  };
}

/// One argument of a message, as inferred from its ICU body.
final class ArgumentSpec {
  /// Creates a spec.
  ArgumentSpec({
    required this.name,
    required this.kind,
    required this.span,
    this.selectOptions = const [],
    this.format,
    this.pluralType,
  });

  /// Name as written in the message.
  final String name;

  /// Inferred kind.
  final ArgumentKind kind;

  /// Where the argument was first seen.
  final SourceSpan span;

  /// Branch labels of a select argument, in document order. Empty otherwise.
  final List<String> selectOptions;

  /// Formatting requested by the message, if any.
  final ArgumentFormat? format;

  /// Whether a plural argument selects on cardinal or ordinal rules.
  final PluralType? pluralType;
}

/// The inferred parameter list of a message.
final class MessageSignature {
  /// Creates a signature.
  MessageSignature(this.arguments, {this.links = const []});

  /// Arguments keyed by name, in order of first appearance.
  final Map<String, ArgumentSpec> arguments;

  /// Every `@:other.key` this message links to, in document order.
  ///
  /// Collected here rather than resolved here: whether the target exists and
  /// what parameters it needs are questions about the project, and this class
  /// only ever reads one message. `LinkResolver` answers them and hands back
  /// the arguments to fold in.
  final List<LinkNode> links;

  /// Infers the signature of [body], reporting conflicts to [diagnostics].
  ///
  /// A name used both as a plural and as a select is a hard error: there is no
  /// single Dart type that could be generated for it.
  /// [extra] are arguments something outside this message contributes — the
  /// messages it links to. Recorded after the walk, so what the message says
  /// about an argument itself still decides its kind, and a disagreement is
  /// the ordinary conflict reported against the link.
  static MessageSignature infer(
    MessageBody body, {
    required String translationKey,
    required DiagnosticCollector diagnostics,
    Iterable<ArgumentSpec> extra = const [],
  }) {
    final arguments = <String, ArgumentSpec>{};
    final links = <LinkNode>[];

    void record(ArgumentSpec spec) => MessageSignature.record(
      arguments,
      spec,
      translationKey: translationKey,
      diagnostics: diagnostics,
    );

    void walk(MessageBody body) {
      for (final node in body.nodes) {
        switch (node) {
          case LiteralNode():
            break;
          case LinkNode():
            // Collected, not resolved: what the target needs is a question
            // about the project, and the answer is folded back in here by
            // `LinkResolver`.
            links.add(node);
          case ArgumentNode():
            record(
              ArgumentSpec(
                name: node.name,
                kind: switch (node.format?.kind) {
                  null => ArgumentKind.plain,
                  ArgumentFormatKind.number => ArgumentKind.number,
                  ArgumentFormatKind.date => ArgumentKind.date,
                  ArgumentFormatKind.time => ArgumentKind.time,
                },
                span: node.span,
                format: node.format,
              ),
            );
          case NumberSignNode():
            record(
              ArgumentSpec(
                name: node.argument,
                kind: ArgumentKind.plural,
                span: node.span,
              ),
            );
          case PluralNode():
            record(
              ArgumentSpec(
                name: node.argument,
                kind: ArgumentKind.plural,
                span: node.span,
                pluralType: node.type,
              ),
            );
            for (final branch in node.cases.values) {
              walk(branch);
            }
          case SelectNode():
            record(
              ArgumentSpec(
                name: node.argument,
                kind: ArgumentKind.select,
                span: node.span,
                selectOptions: node.cases.keys.toList(growable: false),
              ),
            );
            for (final branch in node.cases.values) {
              walk(branch);
            }
        }
      }
    }

    walk(body);
    // Added rather than recorded: these have already been checked against
    // this message by the resolver that produced them, and a second check
    // would report a second copy of every conflict it found.
    for (final spec in extra) {
      arguments.putIfAbsent(spec.name, () => spec);
    }
    return MessageSignature(arguments, links: links);
  }

  /// Folds [spec] into [arguments], reporting a kind conflict.
  ///
  /// Shared with `LinkResolver`, which merges the arguments of a link's target
  /// into the message that links to it: the rules for two references to one
  /// name are the same whether both are in this string or one came from
  /// another message, and two copies of them would be two chances to differ.
  /// [via] is the link that brought [spec] in, when one did: the fix for a
  /// conflict the message did not write itself is in another message, and
  /// "rename one of them" would be advice about the wrong file.
  static void record(
    Map<String, ArgumentSpec> arguments,
    ArgumentSpec spec, {
    required String translationKey,
    required DiagnosticCollector diagnostics,
    String? via,
  }) {
    final existing = arguments[spec.name];
    if (existing == null) {
      arguments[spec.name] = spec;
      return;
    }
    // A plain `{count}` reference inside a plural branch is not a conflict:
    // it carries no type information of its own, so the other kind wins.
    final bothTyped =
        existing.kind != ArgumentKind.plain && spec.kind != ArgumentKind.plain;
    if (bothTyped && existing.kind.category != spec.kind.category) {
      diagnostics.add(
        Diagnostic.error(
          code: 'argument_kind_conflict',
          message:
              'Argument "${spec.name}" is used both as a '
              '${existing.kind.label} and as a ${spec.kind.label}.',
          span: spec.span,
          translationKey: translationKey,
          details: via == null
              ? 'One message cannot generate two different Dart types for '
                    'the same parameter. Rename one of them.'
              : 'The ${spec.kind.label} comes from "$via", which this '
                    'message links to, so both land on one parameter here '
                    'and there is no Dart type that could be both.\n'
                    'Rename the argument in one of the two messages, or '
                    'write the words out instead of linking.',
        ),
      );
      return;
    }
    // Same type family: keep whichever reference determines the signature.
    // `{d, date} at {d, time}` and `{count}` inside a plural both land here.
    if (spec.kind.precedence > existing.kind.precedence) {
      arguments[spec.name] = spec;
    }
  }
}
