import 'package:l10n_plus_generator/src/diagnostic.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// A key a locale has and the base locale does not.
///
/// An error by default, because the base locale is the API contract and a key
/// nothing can reach is usually a typo. A team working through a TMS meets the
/// other case: a key is removed from the base locale and the translations for
/// it keep arriving for a while, and nobody can build until every language has
/// caught up.
String _config(String? extraKeys) =>
    '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
${extraKeys ?? ''}
''';

const Map<String, String> _bundle = {
  'en.json': '{"kept": "Kept"}',
  'ru.json': '{"kept": "Сохранено", "removed": "Удалено"}',
};

void main() {
  test('an extra key is an error by default', () {
    final result = runGenerator(_bundle, configYaml: _config(null));

    expect(errorsOf(result), ['extra_key']);
    expect(result.files, isEmpty);
  });

  test('extra_keys: error is the default spelled out', () {
    final result = runGenerator(
      _bundle,
      configYaml: _config('extra_keys: error'),
    );
    expect(errorsOf(result), ['extra_key']);
  });

  group('extra_keys: warn', () {
    test('generation succeeds and the key is only a warning', () {
      final result = runGenerator(
        _bundle,
        configYaml: _config('extra_keys: warn'),
      );

      expect(errorsOf(result), isEmpty);
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'extra_key',
      );
      expect(diagnostic.severity, Severity.warning);
      expect(diagnostic.translationKey, 'removed');
      expect(diagnostic.details, contains('ignored'));
    });

    test('the key does not reach the generated API', () {
      final result = runGenerator(
        _bundle,
        configYaml: _config('extra_keys: warn'),
      );

      final source = result.files.single.contents;
      expect(source, contains('get kept'));
      expect(source, isNot(contains('removed')));
      expect(source, isNot(contains('Удалено')));
    });

    test('the output is what removing the key by hand would give', () {
      final withExtra = runGenerator(
        _bundle,
        configYaml: _config('extra_keys: warn'),
      );
      final without = runGenerator({
        'en.json': '{"kept": "Kept"}',
        'ru.json': '{"kept": "Сохранено"}',
      }, configYaml: _config('extra_keys: warn'));

      expect(withExtra.files.single.contents, without.files.single.contents);
    });

    test('a whole extra group is one warning, and says how many keys', () {
      final result = runGenerator({
        'en.json': '{"kept": "Kept"}',
        'ru.json':
            '{"kept": "Сохранено", '
            '"gone": {"a": "А", "b": "Б", "c": "В"}}',
      }, configYaml: _config('extra_keys: warn'));

      expect(errorsOf(result), isEmpty);
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code == 'extra_key',
      );
      expect(diagnostic.translationKey, 'gone');
      expect(diagnostic.message, contains('(3 keys)'));
    });

    test('it excuses nothing else', () {
      // The point of the option is a key the base locale no longer has, not a
      // locale that disagrees with the base about a message it does have.
      final result = runGenerator({
        'en.json': '{"a": "{name} here"}',
        'ru.json': '{"a": "тут", "b": "лишний"}',
      }, configYaml: _config('extra_keys: warn'));

      expect(errorsOf(result), contains('missing_placeholder'));
      expect(codesOf(result), contains('extra_key'));
    });

    test('a missing key is still an error', () {
      // No extra key to pair it with, so this is a plain `missing_key`:
      // tolerating a translation that outlived its key does not tolerate a
      // key that has no translation.
      final result = runGenerator({
        'en.json': '{"a": "A", "b": "B"}',
        'ru.json': '{"a": "А"}',
      }, configYaml: _config('extra_keys: warn'));

      expect(errorsOf(result), contains('missing_key'));
    });

    test('one missing and one extra key read as a rename, and still fail', () {
      final result = runGenerator({
        'en.json': '{"a": "A", "b": "B"}',
        'ru.json': '{"a": "А", "c": "В"}',
      }, configYaml: _config('extra_keys: warn'));

      expect(errorsOf(result), contains('renamed_key'));
      expect(codesOf(result), isNot(contains('missing_key')));
      expect(codesOf(result), isNot(contains('extra_key')));
    });
  });

  group('configuration', () {
    test('an unknown value is reported and the default is kept', () {
      final result = runGenerator(
        _bundle,
        configYaml: _config('extra_keys: ignore'),
      );

      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'invalid_config',
      );
      expect(diagnostic.message, contains('extra_keys'));
      expect(diagnostic.details, contains('error'));
      expect(diagnostic.details, contains('warn'));
      // Falling back to the strict default: an unreadable option must not
      // quietly loosen the build.
      expect(errorsOf(result), contains('extra_key'));
    });

    test('a non string is reported', () {
      final result = runGenerator(
        _bundle,
        configYaml: _config('extra_keys: true'),
      );
      expect(codesOf(result), contains('invalid_config'));
      expect(errorsOf(result), contains('extra_key'));
    });
  });
}
