@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/fixture.dart';

/// Formatting a date before the ICU symbols are loaded.
///
/// `DateFormat.yMMMd('ru')` throws while it is *constructed*, so the failure
/// arrives on the first read of the generated top level final, carrying
/// intl's message — which is true and says nothing about the initializer this
/// generator wrote for exactly this purpose. Nothing can fix it lazily:
/// `initializeDateFormatting` is asynchronous and a field initializer is not.
/// So the generated code turns the error into one that names the call.
const String _config = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
flutter:
  enabled: false
''';

void main() {
  test('every date formatter is built through the helper', () {
    final result = runGenerator({
      'en.json': '{"when": "{d, date, yMMMd}"}',
      'ru.json': '{"when": "{d, date, yMMMd}"}',
    }, configYaml: _config);

    expect(errorsOf(result), isEmpty);
    final source = result.files.single.contents;

    expect(source, contains('DateFormat _dateFormat('));
    expect(
      source,
      contains(
        "_ruDateYMMMd = _dateFormat('ru', () => DateFormat.yMMMd('ru'))",
      ),
    );
    // The message names the generated initializer, not just intl's advice to
    // "call initializeDateFormatting".
    expect(source, contains('await initializeAppLocalizationsFormatting()'));
    expect(source, contains('Date symbols for'));
  });

  test('the helper is not emitted when nothing formats a date', () {
    final result = runGenerator({
      'en.json': '{"n": "{v, number}"}',
    }, configYaml: _config);

    final source = result.files.single.contents;
    expect(source, contains('NumberFormat'));
    // A number format needs no symbols, so a project that only formats
    // numbers gets neither the initializer nor the helper.
    expect(source, isNot(contains('_dateFormat(')));
    expect(source, isNot(contains('initializeAppLocalizationsFormatting')));
  });

  test('the helper is declared once when the library is split per locale', () {
    final result = runGenerator({
      'en.json': '{"when": "{d, date, yMMMd}"}',
      'ru.json': '{"when": "{d, date, yMMMd}"}',
    }, configYaml: '$_config\nfile_per_locale: true\n');

    expect(errorsOf(result), isEmpty);
    final all = result.files.map((f) => f.contents).join();
    // The parts are one library with the shared file, so a second declaration
    // would not compile.
    expect('DateFormat _dateFormat('.allMatches(all), hasLength(1));

    final shared = result.files
        .firstWhere((f) => f.path.endsWith('app_localizations.g.dart'))
        .contents;
    expect(shared, contains('DateFormat _dateFormat('));
  });
}
