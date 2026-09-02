import 'dart:io';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _configYaml = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

/// Builds a project on disk and reports which of its keys look unused.
///
/// [dart] is keyed by path relative to the project root, so a test can put a
/// file inside `lib/generated` and check that it is not mistaken for a use.
({List<Diagnostic> unused, GenerationResult result}) _scan({
  required Map<String, String> translations,
  required Map<String, String> dart,
}) {
  final root = Directory.systemTemp.createTempSync('l10n_plus_unused');
  addTearDown(() => root.deleteSync(recursive: true));

  translations.forEach((name, content) {
    final file = File(p.join(root.path, 'translations', name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });
  dart.forEach((name, content) {
    final file = File(p.join(root.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });

  final diagnostics = DiagnosticCollector();
  final config = L10nPlusConfig.parse(
    _configYaml,
    uri: Uri.parse('file://${root.path}/l10n_plus.yaml'),
    diagnostics: diagnostics,
  )!;
  final generator = L10nPlusGenerator(config: config, projectRoot: root.path);
  final result = generator.run();
  expect(
    result.diagnostics.where((d) => d.severity == Severity.error),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format(highlight: false)).join(),
  );
  return (unused: generator.findUnusedKeys(result), result: result);
}

List<String> _unusedKeys({
  required Map<String, String> translations,
  required Map<String, String> dart,
}) => _scan(
  translations: translations,
  dart: dart,
).unused.map((d) => d.translationKey!).toList();

const Map<String, String> _twoKeys = {
  'en.json': '{"auth": {"title": "Log in"}, "wallet": {"balance": "Balance"}}',
};

void main() {
  group('name matching', () {
    test('a key nothing mentions is reported', () {
      expect(
        _unusedKeys(
          translations: _twoKeys,
          dart: {'lib/main.dart': 'void main() { print(t.auth.title); }'},
        ),
        ['wallet.balance'],
      );
    });

    test('a key everything mentions is not', () {
      expect(
        _unusedKeys(
          translations: _twoKeys,
          dart: {
            'lib/a.dart': 'final a = t.auth.title;',
            'lib/b.dart': 'final b = t.wallet.balance;',
          },
        ),
        isEmpty,
      );
    });

    test('the member name is what counts, not the path', () {
      // Reached through a local, which no path based scan would see.
      expect(
        _unusedKeys(
          translations: _twoKeys,
          dart: {
            'lib/a.dart':
                'void f() { final w = t.wallet; print(w.balance); }\n'
                'final x = t.auth.title;',
          },
        ),
        isEmpty,
      );
    });

    test('a cascade counts as a use', () {
      expect(
        _unusedKeys(
          translations: _twoKeys,
          dart: {'lib/a.dart': 'void f() { t..auth..title..wallet..balance; }'},
        ),
        isEmpty,
      );
    });

    test('a null aware access counts as a use', () {
      expect(
        _unusedKeys(
          translations: _twoKeys,
          dart: {
            'lib/a.dart':
                'final a = t?.auth?.title; final b = t?.wallet?.balance;',
          },
        ),
        isEmpty,
      );
    });

    test('a method call counts, so arguments do not hide a message', () {
      expect(
        _unusedKeys(
          translations: {'en.json': '{"greet": "Hello, {name}"}'},
          dart: {'lib/a.dart': "final a = t.greet(name: 'Alex');"},
        ),
        isEmpty,
      );
    });

    test('two keys with the same member name share a fate', () {
      // The documented over-approximation: `title` is used once, and both
      // keys called `title` count as used. Reporting the other one would risk
      // someone deleting a live translation.
      expect(
        _unusedKeys(
          translations: {
            'en.json':
                '{"auth": {"title": "Log in"}, "wallet": {"title": "Wallet"}}',
          },
          dart: {'lib/a.dart': 'final a = t.auth.title;'},
        ),
        isEmpty,
      );
    });

    test('the key is normalized before it is looked for', () {
      // `quoted_key` generates `quotedKey`, and that is the name to search.
      expect(
        _unusedKeys(
          translations: {'en.json': '{"quoted_key": "A", "other": "B"}'},
          dart: {'lib/a.dart': 'final a = t.quotedKey;'},
        ),
        ['other'],
      );
    });
  });

  group('what is searched', () {
    test('the generated output is not a use of itself', () {
      // Every generated file declares `get balance`, and the locale enum has
      // `.en`. Counting those would make every key look used, always.
      final unused = _unusedKeys(
        translations: _twoKeys,
        dart: {
          'lib/generated/app_localizations.g.dart':
              'class X { String get balance => "x"; }\n'
              'final y = something.balance;',
          'lib/main.dart': 'final a = t.auth.title;',
        },
      );
      expect(unused, ['wallet.balance']);
    });

    test('.dart_tool and build are skipped', () {
      final unused = _unusedKeys(
        translations: _twoKeys,
        dart: {
          '.dart_tool/x.dart': 'final a = something.balance;',
          'build/y.dart': 'final a = something.balance;',
          'lib/main.dart': 'final a = t.auth.title;',
        },
      );
      expect(unused, ['wallet.balance']);
    });

    test('tests and bin count, because they use the API too', () {
      expect(
        _unusedKeys(
          translations: _twoKeys,
          dart: {
            'lib/main.dart': 'final a = t.auth.title;',
            'test/a_test.dart': 'final b = t.wallet.balance;',
          },
        ),
        isEmpty,
      );
    });

    test('a project with no Dart at all reports everything', () {
      expect(_unusedKeys(translations: _twoKeys, dart: const {}), [
        'auth.title',
        'wallet.balance',
      ]);
    });
  });

  group('the report', () {
    test('points at the key in the base locale file', () {
      final scan = _scan(
        translations: _twoKeys,
        dart: {'lib/main.dart': 'final a = t.auth.title;'},
      );
      final diagnostic = scan.unused.single;
      expect(diagnostic.code, 'unused_key');
      expect(diagnostic.severity, Severity.warning);
      expect(diagnostic.span!.text, '"balance"');
      expect(diagnostic.details, contains('".balance"'));
      expect(diagnostic.details, contains('file(s) searched'));
    });

    test('every key of the base locale is checked', () {
      final scan = _scan(
        translations: _twoKeys,
        dart: {'lib/main.dart': 'final a = t.auth.title;'},
      );
      expect(scan.result.keys.map((key) => key.path), [
        'auth.title',
        'wallet.balance',
      ]);
      expect(scan.result.keys.map((key) => key.dartName), ['title', 'balance']);
    });
  });

  group('the scanner on its own', () {
    test('reads names out of text', () {
      final names = UnusedKeyScanner.referencedNames([
        const DartSource(path: 'a.dart', content: 'x.one; y?.two; z..three;'),
      ]);
      expect(names, containsAll(['one', 'two', 'three']));
    });

    test('a bare identifier is not a member access', () {
      final names = UnusedKeyScanner.referencedNames([
        const DartSource(path: 'a.dart', content: 'final title = 1;'),
      ]);
      expect(names, isNot(contains('title')));
    });
  });
}
