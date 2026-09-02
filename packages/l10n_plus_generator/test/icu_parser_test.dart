import 'package:l10n_plus_generator/src/ast/message_ast.dart';
import 'package:l10n_plus_generator/src/icu/icu_parser.dart';
import 'package:source_span/source_span.dart';
import 'package:test/test.dart';

IcuParseResult parse(String message) {
  final file = SourceFile.fromString(message, url: Uri.parse('mem:test.json'));
  return IcuMessageParser.parse(
    message,
    valueSpan: file.span(0, message.length),
    contentOffset: 0,
    translationKey: 'test.key',
  );
}

MessageBody body(String message) {
  final result = parse(message);
  expect(
    result.diagnostics.where((d) => d.severity.name == 'error'),
    isEmpty,
    reason: result.diagnostics.map((d) => d.message).join('\n'),
  );
  return result.body!;
}

List<String> errorCodes(String message) => parse(message).diagnostics
    .where((d) => d.severity.name == 'error')
    .map((d) => d.code)
    .toList();

void main() {
  group('plain text', () {
    test('parses as a single literal', () {
      final nodes = body('Log in').nodes;
      expect(nodes, hasLength(1));
      expect((nodes.single as LiteralNode).value, 'Log in');
    });

    test('parses an empty message', () {
      expect(body('').nodes, isEmpty);
    });
  });

  group('placeholders', () {
    test('splits literal and argument nodes', () {
      final nodes = body('Welcome back, {name}!').nodes;
      expect(nodes, hasLength(3));
      expect((nodes[0] as LiteralNode).value, 'Welcome back, ');
      expect((nodes[1] as ArgumentNode).name, 'name');
      expect((nodes[2] as LiteralNode).value, '!');
    });

    test('tolerates whitespace inside braces', () {
      final nodes = body('Hi { name }').nodes;
      expect((nodes[1] as ArgumentNode).name, 'name');
    });

    test('reports an unclosed placeholder', () {
      expect(errorCodes('Hi {name'), contains('icu_unclosed_argument'));
    });

    test('reports a missing argument name', () {
      expect(errorCodes('Hi {}'), contains('icu_missing_argument_name'));
    });

    test('reports a stray closing brace', () {
      expect(errorCodes('Hi }'), contains('icu_unbalanced_brace'));
    });
  });

  group('quoting', () {
    test('keeps ordinary apostrophes literal', () {
      expect((body("l'ami").nodes.single as LiteralNode).value, "l'ami");
    });

    test('doubled apostrophes become one', () {
      expect((body("it''s").nodes.single as LiteralNode).value, "it's");
    });

    test('quotes braces', () {
      expect(
        (body("'{'not an arg'}'").nodes.single as LiteralNode).value,
        '{not an arg}',
      );
    });
  });

  group('plural', () {
    test('parses exact and category branches', () {
      final plural =
          body('{count, plural, =0{None} one{One} other{# items}}').nodes.single
              as PluralNode;

      expect(plural.argument, 'count');
      expect(plural.cases.keys, [
        const ExactPluralCase(0),
        const CategoryPluralCase(PluralCategory.one),
        const CategoryPluralCase(PluralCategory.other),
      ]);
      final other =
          plural.cases[const CategoryPluralCase(PluralCategory.other)]!;
      expect((other.nodes.first as NumberSignNode).argument, 'count');
    });

    test('parses nested arguments inside branches', () {
      final plural =
          body('{count, plural, other{{count} of {total}}}').nodes.single
              as PluralNode;
      final other = plural.cases.values.single;
      expect(other.nodes.whereType<ArgumentNode>().map((n) => n.name), [
        'count',
        'total',
      ]);
    });

    test('requires an other branch', () {
      expect(
        errorCodes('{count, plural, one{One}}'),
        contains('icu_missing_other_branch'),
      );
    });

    test('rejects an unknown category', () {
      expect(
        errorCodes('{count, plural, lots{Many} other{Some}}'),
        contains('icu_invalid_branch'),
      );
    });

    test('rejects a duplicate branch', () {
      expect(
        errorCodes('{count, plural, one{a} one{b} other{c}}'),
        contains('icu_duplicate_branch'),
      );
    });

    test('rejects a missing branch body', () {
      expect(
        errorCodes('{count, plural, other}'),
        contains('icu_invalid_branch'),
      );
    });

    test('rejects an unterminated plural', () {
      expect(
        errorCodes('{count, plural, other{items}'),
        contains('icu_unclosed_argument'),
      );
    });

    test('parses an offset', () {
      final plural =
          body('{count, plural, offset:1 =0{none} one{one other} other{# others}}')
                  .nodes
                  .single
              as PluralNode;
      expect(plural.offset, 1);
      expect(plural.type, PluralType.cardinal);
    });

    test('rejects an offset after the branches', () {
      expect(
        errorCodes('{count, plural, other{#} offset:1}'),
        contains('icu_unsupported_offset'),
      );
    });

    test('rejects a malformed offset', () {
      expect(
        errorCodes('{count, plural, offset:x other{#}}'),
        contains('icu_unsupported_offset'),
      );
    });

    test('defaults the offset to zero', () {
      final plural =
          body('{count, plural, other{#}}').nodes.single as PluralNode;
      expect(plural.offset, 0);
    });
  });

  group('select', () {
    test('parses branches in document order', () {
      final select =
          body(
                '{gender, select, male{He} female{She} other{They}}',
              ).nodes.single
              as SelectNode;
      expect(select.argument, 'gender');
      expect(select.cases.keys, ['male', 'female', 'other']);
    });

    test('requires an other branch', () {
      expect(
        errorCodes('{gender, select, male{He}}'),
        contains('icu_missing_other_branch'),
      );
    });

    test('supports plural nested in select', () {
      final select =
          body('{kind, select, card{{count, plural, other{# cards}}} other{none}}')
                  .nodes
                  .single
              as SelectNode;
      expect(select.cases['card']!.nodes.single, isA<PluralNode>());
    });
  });

  group('selectordinal', () {
    test('parses like a plural but with the ordinal type', () {
      final node =
          body(
                '{n, selectordinal, one{#st} two{#nd} few{#rd} other{#th}}',
              ).nodes.single
              as PluralNode;
      expect(node.type, PluralType.ordinal);
      expect(node.cases.keys.map((c) => c.label), [
        'one',
        'two',
        'few',
        'other',
      ]);
    });

    test('requires an other branch', () {
      final result = parse('{n, selectordinal, one{#st}}');
      expect(result.diagnostics.single.code, 'icu_missing_other_branch');
      expect(result.diagnostics.single.message, contains('selectordinal'));
    });

    test('rejects an offset', () {
      final result = parse('{n, selectordinal, offset:1 other{#th}}');
      expect(result.diagnostics.single.code, 'icu_unsupported_offset');
      expect(result.diagnostics.single.message, contains('only allowed'));
    });
  });

  group('unsupported types', () {
    test('unknown types are rejected', () {
      expect(
        errorCodes('{amount, money, GBP}'),
        contains('icu_unsupported_type'),
      );
    });
  });

  test('reports the position of a nested error', () {
    final result = parse('ok {count, plural, one{x}}');
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.span!.start.column, 3);
  });
}
