import 'package:l10n_plus_generator/src/source/span_json.dart';
import 'package:test/test.dart';

JsonValue parse(String source) =>
    SpanJsonParser.parse(source, uri: Uri.parse('mem:test.json'));

void main() {
  test('parses nested objects and keeps key spans', () {
    final root =
        parse('{\n  "auth": {\n    "title": "Log in"\n  }\n}') as JsonObject;
    final auth = root.entries.single;
    expect(auth.key, 'auth');
    expect(auth.keySpan.start.line, 1);

    final title = (auth.value as JsonObject).entries.single;
    expect((title.value as JsonString).value, 'Log in');
    expect(title.value.span.start.line, 2);
  });

  test('exposes the content offset of plain strings', () {
    final root = parse('{"a": "hi"}') as JsonObject;
    final value = root.entries.single.value as JsonString;
    expect(value.contentOffset, 7);
  });

  test('drops the content offset when escapes shift positions', () {
    final root = parse(r'{"a": "hi\n"}') as JsonObject;
    final value = root.entries.single.value as JsonString;
    expect(value.value, 'hi\n');
    expect(value.contentOffset, isNull);
  });

  test('decodes escape sequences', () {
    final root = parse(r'{"a": "A\t\"\\"}') as JsonObject;
    expect((root.entries.single.value as JsonString).value, 'A\t"\\');
  });

  test('preserves duplicate members so they can be reported', () {
    final root = parse('{"a": "1", "a": "2"}') as JsonObject;
    expect(root.entries, hasLength(2));
  });

  test('parses the remaining JSON value types', () {
    final root =
        parse('{"n": 1.5e2, "b": true, "z": null, "l": [1, 2]}') as JsonObject;
    expect((root.entries[0].value as JsonNumber).value, 150);
    expect((root.entries[1].value as JsonBoolean).value, isTrue);
    expect(root.entries[2].value, isA<JsonNull>());
    expect((root.entries[3].value as JsonArray).items, hasLength(2));
  });

  group('errors carry a position', () {
    void expectFailure(String source, {required int line}) {
      expect(
        () => parse(source),
        throwsA(
          isA<SpanJsonException>().having(
            (e) => e.span.start.line,
            'line',
            line,
          ),
        ),
      );
    }

    test('unterminated string', () => expectFailure('{"a": "x}', line: 0));
    test('missing colon', () => expectFailure('{"a" "x"}', line: 0));
    test('trailing comma', () => expectFailure('{"a": "x",}', line: 0));
    test('trailing content', () => expectFailure('{} {}', line: 0));
    test(
      'nested failure keeps its line',
      () => expectFailure('{\n"a": {\n"b": }\n}', line: 2),
    );
  });
}
