import 'package:l10n_plus_generator/src/plural/cldr_plural_rules.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  group('key structure', () {
    test('accepts identical trees', () {
      final result = runGenerator({
        'en.json': '{"auth": {"title": "Log in"}}',
        'ru.json': '{"auth": {"title": "Войти"}}',
      });
      expect(errorsOf(result), isEmpty);
      expect(result.files, hasLength(1));
    });

    test('reports a missing key', () {
      final result = runGenerator({
        'en.json': '{"a": "A", "b": "B"}',
        'ru.json': '{"a": "А"}',
      });
      expect(errorsOf(result), ['missing_key']);
      expect(result.diagnostics.first.translationKey, 'b');
    });

    test('reports an extra key', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'ru.json': '{"a": "А", "c": "Ц"}',
      });
      expect(errorsOf(result), ['extra_key']);
      expect(result.diagnostics.first.details, contains('base locale'));
    });

    test('reports a group where a message is expected', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'ru.json': '{"a": {"b": "Б"}}',
      });
      expect(errorsOf(result), contains('key_kind_mismatch'));
    });
  });

  group('arguments', () {
    test('reports a missing placeholder', () {
      final result = runGenerator({
        'en.json': '{"hello": "Hello {name}"}',
        'ru.json': '{"hello": "Привет"}',
      });
      expect(errorsOf(result), ['missing_placeholder']);
      expect(result.diagnostics.first.details, contains('argument is missing'));
    });

    test('reports an extra placeholder', () {
      final result = runGenerator({
        'en.json': '{"hello": "Hello"}',
        'ru.json': '{"hello": "Привет, {name}"}',
      });
      expect(errorsOf(result), ['extra_placeholder']);
    });

    test('reports a plural used where the base has a placeholder', () {
      final result = runGenerator({
        'en.json': '{"n": "{count} items"}',
        'ru.json': '{"n": "{count, plural, other{# штук}}"}',
      });
      final diagnostic = result.diagnostics.first;
      expect(diagnostic.code, 'argument_kind_mismatch');
      expect(diagnostic.details, contains('type: placeholder'));
      expect(diagnostic.details, contains('type: plural'));
    });

    test('reports mismatched select branches', () {
      final result = runGenerator({
        'en.json': '{"g": "{gender, select, male{He} other{They}}"}',
        'ru.json': '{"g": "{gender, select, male{Он} female{Она} other{Они}}"}',
      });
      final diagnostic = result.diagnostics.first;
      expect(diagnostic.code, 'select_branch_mismatch');
      expect(diagnostic.details, contains('unexpected: female'));
    });

    test('rejects one name used as both plural and select', () {
      final result = runGenerator({
        'en.json': '{"x": "{a, plural, other{#}} {a, select, y{Y} other{N}}"}',
      });
      expect(errorsOf(result), contains('argument_kind_conflict'));
    });
  });

  group('plural categories', () {
    test('warns when a locale does not cover all of its categories', () {
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, one{# item} other{# items}}"}',
        'ru.json': '{"n": "{count, plural, one{# шт} other{# штук}}"}',
      });
      expect(errorsOf(result), isEmpty);
      final warning = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_plural_category',
      );
      expect(warning.message, contains('few, many'));
      expect(result.files, isNotEmpty, reason: 'warnings must not block');
    });

    test('warns about a branch that can never match', () {
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, one{#} few{#} other{#}}"}',
      });
      expect(codesOf(result), contains('unused_plural_category'));
    });

    test('rejects plurals in a language without known rules', () {
      // Welsh has six categories and is not in the table. Adding it is what
      // should break this test; pick another absent language then.
      expect(CldrPluralRules.forLanguage('cy'), isNull);
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, other{# items}}"}',
        'cy.json': '{"n": "{count, plural, other{# eitem}}"}',
      });
      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'unknown_plural_language',
      );
      expect(diagnostic.details, contains('Supported languages'));
    });
  });

  group('a diagnostic about a subtree says how big it is', () {
    test('a missing group counts the messages it covers', () {
      final result = runGenerator({
        'en.json':
            '{"wallet": {"a": "A", "b": "B", "c": {"d": "D", "e": "E"}}}',
        'ru.json': '{}',
      });
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_key',
      );
      expect(diagnostic.message, contains('"wallet"'));
      expect(diagnostic.details, contains('covers 4 messages'));
    });

    test('a single missing message says nothing about a count', () {
      final result = runGenerator({
        'en.json': '{"a": "A", "b": "B"}',
        'ru.json': '{"a": "А"}',
      });
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_key',
      );
      expect(diagnostic.details, isNot(contains('covers')));
    });

    test('the base file is named, not only the line', () {
      // With one file per feature per locale, a bare line number names
      // nothing.
      final result = runGenerator(
        {
          'en/wallet.json': '{"balance": "Balance"}',
          'en/auth.json': '{"login": "Log in"}',
          'ru/wallet.json': '{"balance": "Баланс"}',
          'ru/auth.json': '{}',
        },
        configYaml: '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
file_pattern: "{locale}/{namespace}"
flutter:
  enabled: false
''',
      );
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_key',
      );
      expect(diagnostic.details, contains('auth.json:1'));
    });
  });

  group('plural type', () {
    test('a plain number where the base has a plural says so', () {
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, one{# item} other{# items}}"}',
        'ru.json': '{"n": "{count, number} штук"}',
      });
      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'plural_type_mismatch',
      );
      expect(diagnostic.message, isNot(contains('null')));
      expect(diagnostic.message, contains('plain number'));
      expect(diagnostic.message, contains('plural'));
    });

    test('a plural where the base has a plain number says so', () {
      final result = runGenerator({
        'en.json': '{"n": "{count, number} items"}',
        'ru.json': '{"n": "{count, plural, one{# штука} other{# штук}}"}',
      });
      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'plural_type_mismatch',
      );
      expect(diagnostic.message, isNot(contains('null')));
      expect(diagnostic.message, contains('plain number'));
    });

    test('cardinal against ordinal still names both', () {
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, one{# item} other{# items}}"}',
        'ru.json': '{"n": "{count, selectordinal, other{#-й}}"}',
      });
      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'plural_type_mismatch',
      );
      expect(diagnostic.message, contains('selectordinal'));
      expect(diagnostic.message, contains('plural'));
      expect(diagnostic.message, isNot(contains('null')));
    });
  });

  group('identifiers', () {
    test('reports keys that collide after normalization', () {
      final result = runGenerator({
        'en.json': '{"user_name": "a", "userName": "b"}',
      });
      expect(errorsOf(result), ['identifier_collision']);
    });

    test('reports select branches that collide as enum values', () {
      final result = runGenerator({
        'en.json': '{"s": "{x, select, a_b{A} aB{B} other{C}}"}',
      });
      expect(errorsOf(result), contains('select_branch_collision'));
    });

    test('reports an enum colliding with the generated class', () {
      final result = runGenerator(
        {
          'en.json':
              '{"app": {"localizations": '
              '"{x, select, a{A} other{B}}"}}',
        },
        configYaml: '''
base_locale: en
fallback_locale: en
class_name: AppLocalizationsX
flutter:
  enabled: false
''',
      );
      expect(errorsOf(result), contains('enum_name_collision'));
    });
  });

  group('input discovery', () {
    test('reports a missing base locale file', () {
      final result = runGenerator({'ru.json': '{"a": "А"}'});
      expect(errorsOf(result), ['missing_base_locale']);
    });

    test('reads region and script from the file name', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'pt_BR.json': '{"a": "A"}',
      });
      expect(errorsOf(result), isEmpty);
      expect(result.files.single.contents, contains("country: 'BR'"));
    });

    test('warns about files whose name is not a locale', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'readme.json': '{}',
      });
      expect(codesOf(result), contains('unrecognized_file_name'));
      expect(errorsOf(result), isEmpty);
    });

    test('a prefixed file name is read as the locale it spells out', () {
      // `app_en` is itself a valid tag (language `app`, region `EN`), so it is
      // accepted as one. The mistake shows up immediately as an `appEn` value
      // in the generated enum rather than being silently mapped to English.
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'app_en.json': '{"a": "A"}',
      });
      expect(errorsOf(result), isEmpty);
      expect(result.files.single.contents, contains('appEn('));
    });

    test('two files of one locale merge, and a shared key collides', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'en.arb': '{"a": "A"}',
      });

      // Better than the old "two files claim this locale": the diagnostic
      // names the key that actually conflicts.
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'duplicate_key');
      expect(diagnostic.translationKey, 'a');
      // Files are read in sorted path order, so `en.arb` defined it first.
      expect(diagnostic.details, contains('en.arb'));
    });

    test('two files of one locale merge when their keys are disjoint', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'en.arb': '{"@@locale": "en", "b": "B"}',
      });

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains("String get a => 'A';"));
      expect(source, contains("String get b => 'B';"));
    });
  });

  test('the generated library exports the type its own API names', () {
    // `AppLocalizations.of(L10nLocale?)` is in the README's own snippet,
    // right under a single import of the generated file. Without the export
    // that snippet does not compile.
    final result = runGenerator({'en.json': '{"a": "A"}'});
    expect(
      result.files.single.contents,
      contains("export 'package:l10n_plus/l10n_plus.dart' show L10nLocale;"),
    );
  });
}
