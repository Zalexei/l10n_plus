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
  MessageSignature(this.arguments);

  /// Arguments keyed by name, in order of first appearance.
  final Map<String, ArgumentSpec> arguments;

  /// Infers the signature of [body], reporting conflicts to [diagnostics].
  ///
  /// A name used both as a plural and as a select is a hard error: there is no
  /// single Dart type that could be generated for it.
  static MessageSignature infer(
    MessageBody body, {
    required String translationKey,
    required DiagnosticCollector diagnostics,
  }) {
    final arguments = <String, ArgumentSpec>{};

    void record(ArgumentSpec spec) {
      final existing = arguments[spec.name];
      if (existing == null) {
        arguments[spec.name] = spec;
        return;
      }
      // A plain `{count}` reference inside a plural branch is not a conflict:
      // it carries no type information of its own, so the other kind wins.
      final bothTyped =
          existing.kind != ArgumentKind.plain &&
          spec.kind != ArgumentKind.plain;
      if (bothTyped && existing.kind.category != spec.kind.category) {
        diagnostics.add(
          Diagnostic.error(
            code: 'argument_kind_conflict',
            message:
                'Argument "${spec.name}" is used both as a '
                '${existing.kind.label} and as a ${spec.kind.label}.',
            span: spec.span,
            translationKey: translationKey,
            details:
                'One message cannot generate two different Dart types for the '
                'same parameter. Rename one of them.',
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

    void walk(MessageBody body) {
      for (final node in body.nodes) {
        switch (node) {
          case LiteralNode():
            break;
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
    return MessageSignature(arguments);
  }
}
