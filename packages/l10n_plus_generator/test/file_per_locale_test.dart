import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

String _config({bool? filePerLocale}) =>
    '''
base_locale: en
fallback_locale: en
${filePerLocale == null ? '' : 'file_per_locale: $filePerLocale'}
flutter:
  enabled: false
''';

const Map<String, String> _project = {
  'en.json': '{"wallet": {"total": "Total: {amount, number}"}}',
  'ru.json': '{"wallet": {"total": "Итого: {amount, number}"}}',
};

List<String> _names(GenerationResult result) =>
    result.files.map((file) => file.path.split('/').last).toList();

String _named(GenerationResult result, String suffix) =>
    result.files.firstWhere((file) => file.path.endsWith(suffix)).contents;

GenerationResult _run({bool? filePerLocale, Map<String, String>? files}) {
  final result = runGenerator(
    files ?? _project,
    configYaml: _config(filePerLocale: filePerLocale),
  );
  expect(
    errorsOf(result),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format(highlight: false)).join(),
  );
  return result;
}

void main() {
  test('off by default, and off means exactly what it did before', () {
    expect(_names(_run()), ['app_localizations.g.dart']);
    expect(
      _run(filePerLocale: false).files.single.contents,
      _run().files.single.contents,
    );
  });

  test('on gives a shared file plus one part per locale', () {
    expect(_names(_run(filePerLocale: true)), [
      'app_localizations.g.dart',
      'app_localizations_en.g.dart',
      'app_localizations_ru.g.dart',
    ]);
  });

  test('the shared file declares the parts and nothing implements there', () {
    final shared = _named(
      _run(filePerLocale: true),
      'generated/app_localizations.g.dart',
    );
    expect(shared, contains("part 'app_localizations_en.g.dart';"));
    expect(shared, contains("part 'app_localizations_ru.g.dart';"));
    expect(shared, contains('enum AppLocale'));
    expect(shared, contains('abstract interface class AppLocalizations'));
    expect(shared, isNot(contains('class AppLocalizationsEn')));
  });

  test('a part names the library it belongs to', () {
    final part = _named(
      _run(filePerLocale: true),
      'app_localizations_en.g.dart',
    );
    expect(part, contains("part of 'app_localizations.g.dart';"));
    expect(part, contains('class AppLocalizationsEn'));
    expect(part, isNot(contains('import ')));
  });

  test('a locale file holds only that locale', () {
    final result = _run(filePerLocale: true);
    final en = _named(result, 'app_localizations_en.g.dart');
    final ru = _named(result, 'app_localizations_ru.g.dart');

    expect(en, contains('Total: '));
    expect(en, isNot(contains('Итого')));
    expect(ru, contains('Итого: '));
    expect(ru, isNot(contains('Total: ')));
  });

  test('each locale carries its own formatters', () {
    final result = _run(filePerLocale: true);
    final en = _named(result, 'app_localizations_en.g.dart');
    final ru = _named(result, 'app_localizations_ru.g.dart');

    // The whole point: adding a formatter to one language must not rewrite
    // another language's file.
    expect(en, contains("_enNumberDecimalPattern = NumberFormat"));
    expect(en, isNot(contains('_ruNumber')));
    expect(ru, contains("_ruNumberDecimalPattern = NumberFormat"));
    expect(ru, isNot(contains('_enNumber')));
  });

  test('imports stay in the shared file, where parts can use them', () {
    final result = _run(filePerLocale: true);
    expect(
      _named(result, 'generated/app_localizations.g.dart'),
      contains("import 'package:intl/intl.dart';"),
    );
    expect(
      _named(result, 'app_localizations_en.g.dart'),
      isNot(contains('package:intl')),
    );
  });

  test('a project with no formatting still imports no intl', () {
    final result = _run(
      filePerLocale: true,
      files: const {'en.json': '{"a": "A"}', 'ru.json': '{"a": "А"}'},
    );
    for (final file in result.files) {
      expect(file.contents, isNot(contains('package:intl')), reason: file.path);
    }
  });

  test('the date symbol initializer stays in the shared file', () {
    final result = _run(
      filePerLocale: true,
      files: const {
        'en.json': '{"d": "{when, date, yMMMd}"}',
        'ru.json': '{"d": "{when, date, yMMMd}"}',
      },
    );
    expect(
      _named(result, 'generated/app_localizations.g.dart'),
      contains('Future<void> initializeAppLocalizationsFormatting()'),
    );
    expect(
      _named(result, 'app_localizations_en.g.dart'),
      isNot(contains('initializeAppLocalizationsFormatting')),
    );
  });

  test('splitting is deterministic', () {
    final first = _run(filePerLocale: true);
    final second = _run(filePerLocale: true);
    expect(_names(first), _names(second));
    for (var index = 0; index < first.files.length; index++) {
      expect(first.files[index].contents, second.files[index].contents);
    }
  });

  test('the class name drives every generated file name', () {
    final result = runGenerator(
      _project,
      configYaml: '''
base_locale: en
fallback_locale: en
class_name: Strings
file_per_locale: true
flutter:
  enabled: false
''',
    );
    expect(errorsOf(result), isEmpty);
    expect(_names(result), [
      'strings.g.dart',
      'strings_en.g.dart',
      'strings_ru.g.dart',
    ]);
    expect(
      _named(result, 'strings_en.g.dart'),
      contains("part of 'strings.g.dart';"),
    );
  });

  test('a locale tag with a region becomes a usable file name', () {
    final result = _run(
      filePerLocale: true,
      files: const {'en.json': '{"a": "A"}', 'pt_BR.json': '{"a": "A"}'},
    );
    expect(_names(result), contains('app_localizations_pt_BR.g.dart'));
    expect(
      _named(result, 'generated/app_localizations.g.dart'),
      contains("part 'app_localizations_pt_BR.g.dart';"),
    );
  });

  test('a non boolean value is rejected', () {
    final result = runGenerator(
      _project,
      configYaml: '''
base_locale: en
fallback_locale: en
file_per_locale: sometimes
flutter:
  enabled: false
''',
    );
    expect(result.diagnostics.first.code, 'invalid_config');
    expect(result.diagnostics.first.message, contains('true or false'));
  });

  test('the Flutter glue is unchanged by splitting', () {
    String glue({required bool split}) {
      final result = runGenerator(
        _project,
        configYaml:
            '''
base_locale: en
fallback_locale: en
file_per_locale: $split
flutter:
  enabled: true
''',
      );
      expect(errorsOf(result), isEmpty);
      return _named(result, 'app_localizations_flutter.g.dart');
    }

    // The import an application writes does not change, so neither does this.
    expect(glue(split: true), glue(split: false));
  });

  group('with fill_missing_from_base', () {
    // A filled message is the base locale's message, formatting included, so
    // it reaches for the base locale's formatter. Every part file belongs to
    // one library, so emitting that formatter again under the same name does
    // not compile.
    const project = {
      'en.json':
          '{"a": "On {d, date, yMMMd}", "b": "Total {n, number, currency:USD}"}',
      'ru.json': '{"a": "От {d, date, yMMMd}"}',
    };
    const config = '''
base_locale: en
fallback_locale: en
file_per_locale: true
fill_missing_from_base: true
flutter:
  enabled: false
''';

    test('a formatter is declared exactly once across the library', () {
      final result = runGenerator(project, configYaml: config);
      expect(errorsOf(result), isEmpty);
      final declarations = <String, List<String>>{};
      final pattern = RegExp(
        r'^final (?:DateFormat|NumberFormat) (_\w+) =',
        multiLine: true,
      );
      for (final file in result.files) {
        for (final match in pattern.allMatches(file.contents)) {
          declarations
              .putIfAbsent(match.group(1)!, () => [])
              .add(file.path.split('/').last);
        }
      }
      final duplicated = {
        for (final entry in declarations.entries)
          if (entry.value.length > 1) entry.key: entry.value,
      };
      expect(duplicated, isEmpty, reason: 'declared in several part files');
    });

    test('the untranslated locale still uses the base locale formatter', () {
      final result = runGenerator(project, configYaml: config);
      final ru = result.files
          .firstWhere((f) => f.path.endsWith('_ru.g.dart'))
          .contents;
      // ru fills `b` from en, which formats in USD as en does.
      expect(ru, contains('_enNumberCurrencyUsd'));
      expect(ru, isNot(contains('final NumberFormat _enNumberCurrencyUsd =')));
    });
  });
}
