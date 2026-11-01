import 'package:l10n_plus/l10n_plus.dart';
import 'package:l10n_plus_generator/src/ast/translation_tree.dart';
import 'package:l10n_plus_generator/src/diagnostic.dart';
import 'package:l10n_plus_generator/src/source/json_source_parser.dart';
import 'package:test/test.dart';

({TranslationDocument? document, List<Diagnostic> diagnostics}) parse(
  String source,
) {
  final diagnostics = DiagnosticCollector();
  final document = const JsonSourceParser().parse(
    content: source,
    uri: Uri.parse('mem:en.json'),
    localeHint: const L10nLocale('en'),
    diagnostics: diagnostics,
  );
  return (document: document, diagnostics: diagnostics.diagnostics);
}

void main() {
  test('builds a nested tree with dotted paths', () {
    final result = parse('{"auth": {"login": {"title": "Log in"}}}');
    expect(result.diagnostics, isEmpty);

    final auth = result.document!.root.child('auth')! as TranslationGroup;
    final login = auth.child('login')! as TranslationGroup;
    final title = login.child('title')! as TranslationLeaf;
    expect(title.path, 'auth.login.title');
    expect(title.raw, 'Log in');
  });

  test('rejects a non object root', () {
    final result = parse('[]');
    expect(result.document, isNull);
    expect(result.diagnostics.single.code, 'invalid_root');
  });

  test('reports invalid leaf types', () {
    // An array is no longer one of them: Milestone 36 made it a list of
    // messages, and an empty one is an empty list.
    final result = parse('{"count": 3, "flag": true, "list": []}');
    expect(
      result.diagnostics.map((d) => d.code),
      everyElement('invalid_leaf_type'),
    );
    expect(result.diagnostics, hasLength(2));
    expect(result.diagnostics.first.details, contains('a number'));
  });

  test('reports duplicate keys with the first location', () {
    final result = parse('{"a": "1",\n "a": "2"}');
    expect(result.diagnostics.single.code, 'duplicate_key');
    expect(result.diagnostics.single.details, contains('line 1'));
  });

  test('reports empty keys', () {
    expect(parse('{"": "x"}').diagnostics.single.code, 'empty_key');
  });

  test('reports malformed JSON with a span', () {
    final result = parse('{"a": }');
    expect(result.document, isNull);
    expect(result.diagnostics.single.code, 'invalid_json');
    expect(result.diagnostics.single.span, isNotNull);
  });
}
