import 'package:l10n_plus_generator/src/diagnostic.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// One rename, one finding.
///
/// Renaming a key in the base locale makes it missing everywhere and leaves
/// the old name extra everywhere, so one edit used to produce two diagnostics
/// per locale, neither aware of the other. At three locales that is four
/// errors for one rename; at twenty it is forty, and the reader has to pair
/// them up by eye.
String _config([String extra = '']) =>
    '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
$extra
''';

void main() {
  group('a rename in the base locale', () {
    test('is one finding instead of two', () {
      final result = runGenerator({
        'en.json': '{"auth": {"headline": "Log in", "hint": "H"}}',
        'ru.json': '{"auth": {"title": "Войти", "hint": "П"}}',
      }, configYaml: _config());

      expect(codesOf(result), ['renamed_key']);
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.severity, Severity.error);
      expect(diagnostic.message, contains('"title"'));
      expect(diagnostic.message, contains('"headline"'));
      expect(diagnostic.translationKey, 'auth.title');
    });

    test('points at the locale that still has the old name', () {
      final result = runGenerator({
        'en.json': '{"headline": "Log in"}',
        'ru.json': '{"title": "Войти"}',
      }, configYaml: _config());

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.span!.text, '"title"');
      expect(diagnostic.details, contains('en.json:'));
      expect(diagnostic.details, contains('ru.json:'));
    });

    test('is reported once per locale that lags behind', () {
      final result = runGenerator({
        'en.json': '{"headline": "Log in"}',
        'ru.json': '{"title": "Войти"}',
        'de.json': '{"title": "Anmelden"}',
        'fr.json': '{"headline": "Connexion"}',
      }, configYaml: _config());

      expect(codesOf(result), ['renamed_key', 'renamed_key']);
      expect(
        result.diagnostics.map((d) => d.span!.sourceUrl!.pathSegments.last),
        containsAll(['de.json', 'ru.json']),
      );
    });

    test('a renamed group carries its subtree, and says how big it is', () {
      final result = runGenerator({
        'en.json': '{"account": {"a": "A", "b": "B", "c": "C"}}',
        'ru.json': '{"profile": {"a": "А", "b": "Б", "c": "В"}}',
      }, configYaml: _config());

      expect(codesOf(result), ['renamed_key']);
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.message, contains('"profile"'));
      expect(diagnostic.message, contains('"account"'));
      expect(diagnostic.details, contains('3 messages'));
    });

    test('names the namespace the two keys share', () {
      final result = runGenerator({
        'en.json': '{"a": {"b": {"headline": "X"}}}',
        'ru.json': '{"a": {"b": {"title": "Х"}}}',
      }, configYaml: _config());

      expect(result.diagnostics.single.details, contains('"a.b"'));
    });
  });

  group('what is not a rename', () {
    test(
      'two of each could be two renames or four edits, so it says neither',
      () {
        final result = runGenerator({
          'en.json': '{"c": "C", "d": "D"}',
          'ru.json': '{"a": "А", "b": "Б"}',
        }, configYaml: _config());

        expect(codesOf(result), isNot(contains('renamed_key')));
        expect(codesOf(result), contains('missing_key'));
        expect(codesOf(result), contains('extra_key'));
      },
    );

    test('a message against a group is a kind mismatch, not a rename', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'ru.json': '{"b": {"x": "Х"}}',
      }, configYaml: _config());

      expect(codesOf(result), isNot(contains('renamed_key')));
    });

    test('a key missing with nothing extra stays a plain missing key', () {
      final result = runGenerator({
        'en.json': '{"a": "A", "b": "B"}',
        'ru.json': '{"a": "А"}',
      }, configYaml: _config());

      expect(codesOf(result), ['missing_key']);
    });

    test('an extra key with nothing missing stays a plain extra key', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'ru.json': '{"a": "А", "b": "Б"}',
      }, configYaml: _config());

      expect(codesOf(result), ['extra_key']);
    });

    test('a rename in a sibling namespace does not pair across namespaces', () {
      final result = runGenerator({
        'en.json': '{"x": {"headline": "A"}, "y": {"hint": "B"}}',
        'ru.json': '{"x": {"headline": "А"}, "y": {"tip": "Б"}}',
      }, configYaml: _config());

      // The pair is inside `y`, and `x` is untouched.
      expect(codesOf(result), ['renamed_key']);
      expect(result.diagnostics.single.translationKey, 'y.tip');
    });
  });

  group('severity follows the pair it replaces', () {
    test('a warning only when both halves are tolerated', () {
      final result = runGenerator({
        'en.json': '{"headline": "Log in"}',
        'ru.json': '{"title": "Войти"}',
      }, configYaml: _config('fill_missing_from_base: true\nextra_keys: warn'));

      expect(errorsOf(result), isEmpty);
      expect(result.diagnostics.single.code, 'renamed_key');
      expect(result.diagnostics.single.severity, Severity.warning);
    });

    test('an error while either half is one', () {
      for (final options in [
        'fill_missing_from_base: true',
        'extra_keys: warn',
      ]) {
        final result = runGenerator({
          'en.json': '{"headline": "Log in"}',
          'ru.json': '{"title": "Войти"}',
        }, configYaml: _config(options));

        expect(errorsOf(result), ['renamed_key'], reason: options);
      }
    });
  });

  test('the finding says what to do when the guess is wrong', () {
    final result = runGenerator({
      'en.json': '{"headline": "Log in"}',
      'ru.json': '{"title": "Войти"}',
    }, configYaml: _config());

    expect(result.diagnostics.single.details, contains('rename it here too'));
    expect(
      result.diagnostics.single.details,
      contains('If they are unrelated'),
    );
  });
}
