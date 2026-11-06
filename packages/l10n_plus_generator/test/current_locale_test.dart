import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `AppLocalizations.current` and the optional top level getter over it.
///
/// What it reads at run time is pinned by `current_locale_runtime_test.dart`
/// against a golden; this file pins what is written and what is refused.
void main() {
  const en = {'en.json': '{"title": "Log in"}'};

  String library(GenerationResult result) =>
      result.files.map((file) => file.contents).join('\n');

  ({L10nPlusConfig? config, List<String> codes}) parse(String extra) {
    final diagnostics = DiagnosticCollector();
    final config = L10nPlusConfig.parse(
      'base_locale: en\n$extra',
      uri: Uri.parse('mem:l10n_plus.yaml'),
      diagnostics: diagnostics,
    );
    return (
      config: config,
      codes: [for (final d in diagnostics.diagnostics) d.code],
    );
  }

  test('the root class always has current, settable through currentLocale', () {
    final source = library(runGenerator(en));
    expect(
      source,
      contains('static AppLocale currentLocale = fallbackLocale;'),
    );
    expect(
      source,
      contains(
        'static AppLocalizations get current => currentLocale.translations;',
      ),
    );
  });

  test('no top level getter unless the project names one', () {
    expect(
      library(runGenerator(en)),
      isNot(contains('=> AppLocalizations.current;')),
    );
  });

  test('global_accessor writes a top level getter over current', () {
    final result = runGenerator(
      en,
      configYaml: '$defaultConfigYaml\nglobal_accessor: t\n',
    );
    expect(errorsOf(result), isEmpty);
    expect(
      library(result),
      contains('AppLocalizations get t => AppLocalizations.current;'),
    );
  });

  test('global_accessor is written once with a file per locale', () {
    final result = runGenerator(
      {...en, 'ru.json': '{"title": "Войти"}'},
      configYaml:
          '$defaultConfigYaml\nglobal_accessor: tr\nfile_per_locale: true\n',
    );
    expect(errorsOf(result), isEmpty);
    expect(
      '=> AppLocalizations.current;'.allMatches(library(result)),
      hasLength(1),
    );
  });

  group('global_accessor is refused when it cannot compile', () {
    for (final name in [
      'T',
      'my-t',
      'if',
      'toString',
      'initializeAppLocalizationsFormatting',
      'createAppLocalizationsController',
      'appLocalizationsSupportedLocales',
    ]) {
      test('"$name"', () {
        final result = parse('global_accessor: "$name"');
        expect(result.config, isNull);
        expect(result.codes, ['invalid_config']);
      });
    }

    test('the generated names follow class_name', () {
      final result = parse(
        'class_name: Strings\nglobal_accessor: initializeStringsFormatting',
      );
      expect(result.config, isNull);
      expect(
        parse('class_name: Strings\nglobal_accessor: t').config,
        isNotNull,
      );
    });
  });

  test('a top level key named current collides with the static member', () {
    for (final key in ['current', 'currentLocale']) {
      final result = runGenerator({'en.json': '{"$key": "Now"}'});
      expect(errorsOf(result), ['identifier_collision'], reason: key);
    }
  });

  test('current below the root is an ordinary key', () {
    final result = runGenerator({
      'en.json': '{"plan": {"current": "Current plan"}}',
    });
    expect(errorsOf(result), isEmpty);
  });
}
