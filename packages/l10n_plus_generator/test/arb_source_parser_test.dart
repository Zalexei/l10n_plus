import 'package:l10n_plus/l10n_plus.dart';
import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:l10n_plus_generator/src/ast/translation_tree.dart';
import 'package:l10n_plus_generator/src/source/arb_source_parser.dart';
import 'package:test/test.dart';

({TranslationDocument? document, List<Diagnostic> diagnostics}) parse(
  String source, {
  L10nLocale? localeHint,
  String fileName = 'en.arb',
}) {
  final diagnostics = DiagnosticCollector();
  final document = const ArbSourceParser().parse(
    content: source,
    uri: Uri.parse('mem:$fileName'),
    localeHint: localeHint,
    diagnostics: diagnostics,
  );
  return (document: document, diagnostics: diagnostics.diagnostics);
}

TranslationLeaf leafAt(TranslationDocument document, String path) {
  TranslationNode node = document.root;
  for (final segment in path.split('.')) {
    node = (node as TranslationGroup).child(segment)!;
  }
  return node as TranslationLeaf;
}

void main() {
  group('locale', () {
    test('@@locale wins over the file name', () {
      final result = parse(
        '{"@@locale": "pt_BR", "a": "A"}',
        localeHint: const L10nLocale('en'),
      );
      expect(result.document!.locale, const L10nLocale('pt', country: 'BR'));
      expect(result.diagnostics, isEmpty);
    });

    test('a gen_l10n style file name is read correctly via @@locale', () {
      // `app_en` is itself a valid tag, so the hint alone would be wrong.
      final result = parse(
        '{"@@locale": "en", "a": "A"}',
        localeHint: L10nLocale.parse('app_en'),
        fileName: 'app_en.arb',
      );
      expect(result.document!.locale, const L10nLocale('en'));
    });

    test('falls back to the file name when @@locale is absent', () {
      final result = parse('{"a": "A"}', localeHint: const L10nLocale('ru'));
      expect(result.document!.locale, const L10nLocale('ru'));
    });

    test('skips a file with neither', () {
      final result = parse('{"a": "A"}', fileName: 'strings.arb');
      expect(result.document, isNull);
      expect(result.diagnostics.single.code, 'unrecognized_file_name');
    });

    test('rejects a malformed @@locale', () {
      final result = parse('{"@@locale": "!!", "a": "A"}');
      expect(result.document, isNull);
      expect(result.diagnostics.single.code, 'invalid_locale_attribute');
    });

    test('ignores other document attributes', () {
      final result = parse(
        '{"@@locale": "en", "@@last_modified": "2026-01-01", "a": "A"}',
      );
      expect(result.diagnostics, isEmpty);
      expect(result.document!.root.children, hasLength(1));
    });
  });

  group('nesting', () {
    test('dotted keys become nested namespaces', () {
      final result = parse(
        '{"@@locale": "en", "auth.login.title": "Log in", '
        '"auth.login.subtitle": "Hi {name}"}',
      );
      expect(result.diagnostics, isEmpty);

      final leaf = leafAt(result.document!, 'auth.login.title');
      expect(leaf.raw, 'Log in');
      expect(leaf.path, 'auth.login.title');
    });

    test('flat keys stay at the top level', () {
      final result = parse('{"@@locale": "en", "loginTitle": "Log in"}');
      expect(result.document!.root.children.single.key, 'loginTitle');
    });

    test('rejects a key that is both a message and a group', () {
      final result = parse(
        '{"@@locale": "en", "auth": "A", "auth.login": "B"}',
      );
      expect(
        result.diagnostics.map((d) => d.code),
        contains('key_kind_mismatch'),
      );
    });

    test('rejects an empty path segment', () {
      final result = parse('{"@@locale": "en", "auth..title": "A"}');
      expect(result.diagnostics.single.code, 'invalid_key');
    });
  });

  group('metadata', () {
    test('reads description and placeholders', () {
      final result = parse('''
{
  "@@locale": "en",
  "greeting": "Hello {name}, you are {age}",
  "@greeting": {
    "description": "Shown on the home screen",
    "placeholders": {
      "name": {"type": "String", "example": "Alex"},
      "age": {"type": "int", "description": "Age in years"}
    }
  }
}
''');
      expect(result.diagnostics, isEmpty);

      final metadata = leafAt(result.document!, 'greeting').metadata;
      expect(metadata.description, 'Shown on the home screen');
      expect(metadata.placeholders['name']!.type, 'String');
      expect(metadata.placeholders['name']!.example, 'Alex');
      expect(metadata.placeholders['age']!.description, 'Age in years');
    });

    test('reports metadata without a message', () {
      final result = parse(
        '{"@@locale": "en", "a": "A", "@b": {"description": "?"}}',
      );
      expect(result.diagnostics.single.code, 'orphan_metadata');
    });

    test('warns about unknown attributes but keeps going', () {
      final result = parse(
        '{"@@locale": "en", "a": "A", "@a": {"nonsense": 1}}',
      );
      expect(result.diagnostics.single.code, 'unknown_metadata_attribute');
      expect(result.diagnostics.single.severity, Severity.warning);
      expect(result.document, isNotNull);
    });

    test('rejects metadata that is not an object', () {
      final result = parse('{"@@locale": "en", "a": "A", "@a": "text"}');
      expect(result.diagnostics.single.code, 'invalid_metadata');
    });
  });

  group('structure', () {
    test('rejects nested objects, since ARB is flat', () {
      final result = parse('{"@@locale": "en", "a": {"b": "B"}}');
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'invalid_leaf_type');
      expect(diagnostic.details, contains('flat format'));
    });

    test('reports duplicate keys', () {
      final result = parse('{"@@locale": "en", "a": "A", "a": "B"}');
      expect(result.diagnostics.single.code, 'duplicate_key');
    });

    test('reports malformed JSON with a span', () {
      final result = parse('{"a": }');
      expect(result.document, isNull);
      expect(result.diagnostics.single.code, 'invalid_json');
      expect(result.diagnostics.single.span, isNotNull);
    });
  });
}
