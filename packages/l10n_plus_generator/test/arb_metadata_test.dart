import 'package:test/test.dart';

import 'support/fixture.dart';

const String _arbConfig = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

String generated(Map<String, String> files) {
  final result = runGenerator(files, configYaml: _arbConfig);
  expect(
    errorsOf(result),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format(highlight: false)).join(),
  );
  return result.files.single.contents;
}

void main() {
  group('declared placeholder types', () {
    test('refine a plain placeholder', () {
      final source = generated({
        'en.arb': '''
{
  "@@locale": "en",
  "cart.items": "You picked {count} of {total}",
  "@cart.items": {
    "placeholders": {
      "count": {"type": "int"},
      "total": {"type": "num"}
    }
  }
}
''',
      });
      expect(
        source,
        contains('String items({required int count, required num total})'),
      );
    });

    test('refine a plural argument', () {
      final source = generated({
        'en.arb': '''
{
  "@@locale": "en",
  "items": "{count, plural, one{# item} other{# items}}",
  "@items": {"placeholders": {"count": {"type": "int"}}}
}
''',
      });
      expect(source, contains('String items({required int count})'));
    });

    test('require an explicit format for a declared DateTime', () {
      final result = runGenerator({
        'en.arb':
            '{"@@locale": "en", "at": "At {when}", '
            '"@at": {"placeholders": {"when": {"type": "DateTime"}}}}',
      }, configYaml: _arbConfig);

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'missing_placeholder_format');
      expect(diagnostic.message, contains('"when"'));
      expect(diagnostic.details, contains('"format": "yMMMd"'));
    });

    test('reject a non numeric type on a plural argument', () {
      final result = runGenerator({
        'en.arb':
            '{"@@locale": "en", "n": "{count, plural, other{#}}", '
            '"@n": {"placeholders": {"count": {"type": "String"}}}}',
      }, configYaml: _arbConfig);

      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'unsupported_placeholder_type',
      );
      expect(diagnostic.message, contains('"String"'));
      expect(diagnostic.message, contains('plural argument'));
      expect(diagnostic.details, contains('double, int, num'));
    });

    test('say nothing about the type gen_l10n writes on every select', () {
      // `"type": "String"` is required by gen_l10n's own schema for a select
      // placeholder, and `Object` is what it writes when the type is left
      // out. Warning about either would put a line on every select of every
      // imported bundle, about something nobody can change.
      for (final declared in ['String', 'Object']) {
        final result = runGenerator({
          'en.arb':
              '{"@@locale": "en", "g": "{g, select, a{A} other{B}}", '
              '"@g": {"placeholders": {"g": {"type": "$declared"}}}}',
        }, configYaml: _arbConfig);

        expect(
          codesOf(result),
          isNot(contains('ignored_placeholder_type')),
          reason: declared,
        );
        expect(errorsOf(result), isEmpty, reason: declared);
      }
    });

    test('warn about a type that contradicts the select', () {
      // An author who declared `int` thinks this argument is a number. That
      // is worth saying, and it is not what an exporter writes.
      for (final declared in ['int', 'num', 'double']) {
        final result = runGenerator({
          'en.arb':
              '{"@@locale": "en", "g": "{g, select, a{A} other{B}}", '
              '"@g": {"placeholders": {"g": {"type": "$declared"}}}}',
        }, configYaml: _arbConfig);

        expect(
          codesOf(result),
          contains('ignored_placeholder_type'),
          reason: declared,
        );
        expect(errorsOf(result), isEmpty, reason: declared);
      }
    });

    test('warn about a declared placeholder the message never uses', () {
      final result = runGenerator({
        'en.arb':
            '{"@@locale": "en", "a": "No arguments here", '
            '"@a": {"placeholders": {"ghost": {"type": "String"}}}}',
      }, configYaml: _arbConfig);

      final warning = result.diagnostics.single;
      expect(warning.code, 'unused_placeholder_declaration');
      expect(warning.details, contains('takes no arguments'));
    });
  });

  group('documentation', () {
    test('descriptions and examples become DartDoc', () {
      final source = generated({
        'en.arb': '''
{
  "@@locale": "en",
  "auth.login.title": "Log in",
  "@auth.login.title": {
    "description": "Title of the login screen"
  },
  "auth.login.greeting": "Hello {name}",
  "@auth.login.greeting": {
    "description": "Greets the signed in user",
    "placeholders": {
      "name": {"type": "String", "description": "First name", "example": "Alex"}
    }
  }
}
''',
      });

      expect(source, contains('/// Title of the login screen'));
      expect(source, contains('/// `en`: Log in'));
      expect(source, contains('/// Greets the signed in user'));
      expect(source, contains('/// - [name]: First name Example: `Alex`.'));
    });

    test('without metadata the base text is still documented', () {
      final source = generated({'en.json': '{"a": "Plain"}'});
      expect(source, contains('/// `en`: Plain'));
    });

    test('square brackets in text are escaped for DartDoc', () {
      final source = generated({'en.json': r'{"a": "See [docs]"}'});
      expect(source, contains(r'/// `en`: See \[docs\]'));
    });
  });

  group('mixed formats', () {
    test('ARB and JSON locales validate against each other', () {
      final result = runGenerator({
        'en.arb': '{"@@locale": "en", "auth.title": "Log in"}',
        'ru.json': '{"auth": {"title": "Войти"}}',
      }, configYaml: _arbConfig);

      expect(errorsOf(result), isEmpty);
      expect(result.files.single.contents, contains("'Войти'"));
    });

    test('a missing key is reported across formats', () {
      final result = runGenerator({
        'en.arb': '{"@@locale": "en", "a": "A", "b": "B"}',
        'ru.json': '{"a": "А"}',
      }, configYaml: _arbConfig);

      expect(errorsOf(result), ['missing_key']);
    });
  });
}
