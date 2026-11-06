import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `global_translations` and `global_getter`: what is written and what is
/// refused. What `current` reads at run time is pinned against the `current`
/// golden by `current_locale_runtime_test.dart`.
void main() {
  const en = {'en.json': '{"title": "Log in"}'};
  const on = '$defaultConfigYaml\nglobal_translations: true\n';

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

  test('off by default: no current, no cell', () {
    final source = library(runGenerator(en));
    expect(source, isNot(contains('current')));
    expect(source, isNot(contains('L10nCurrent')));
  });

  test('on: the root class gets current and its companions', () {
    final result = runGenerator(en, configYaml: on);
    expect(errorsOf(result), isEmpty);
    final source = library(result);
    for (final member in [
      'static final L10nCurrent<AppLocale> currentCell',
      'static AppLocale get currentLocale',
      'static AppLocalizations get current',
      'static void setCurrentLocale(AppLocale locale)',
      'static void resetCurrent()',
    ]) {
      expect(source, contains(member));
    }
    expect(source, isNot(contains('=> AppLocalizations.current;')));
  });

  test('global_getter writes a top level getter, once', () {
    final result = runGenerator({
      ...en,
      'ru.json': '{"title": "Войти"}',
    }, configYaml: '${on}global_getter: tr\nfile_per_locale: true\n');
    expect(errorsOf(result), isEmpty);
    expect(
      'AppLocalizations get tr => AppLocalizations.current;'.allMatches(
        library(result),
      ),
      hasLength(1),
    );
  });

  test('global_getter without global_translations is refused', () {
    final result = parse('global_getter: t');
    expect(result.config, isNull);
    expect(result.codes, ['invalid_config']);
  });

  group('global_getter is refused when it cannot compile', () {
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
        final result = parse(
          'global_translations: true\nglobal_getter: "$name"',
        );
        expect(result.config, isNull);
        expect(result.codes, ['invalid_config']);
      });
    }

    test('the generated names follow class_name', () {
      expect(
        parse(
          'class_name: Strings\nglobal_translations: true\n'
          'global_getter: initializeStringsFormatting',
        ).config,
        isNull,
      );
      expect(
        parse(
          'class_name: Strings\nglobal_translations: true\nglobal_getter: t',
        ).config,
        isNotNull,
      );
    });
  });

  group('a top level key named after a member', () {
    const members = [
      'current',
      'currentCell',
      'currentLocale',
      'resetCurrent',
      'setCurrentLocale',
    ];

    test('collides with the option on', () {
      for (final key in members) {
        final result = runGenerator({
          'en.json': '{"$key": "Now"}',
        }, configYaml: on);
        expect(errorsOf(result), ['identifier_collision'], reason: key);
      }
    });

    test('is an ordinary key with it off', () {
      for (final key in members) {
        final result = runGenerator({'en.json': '{"$key": "Now"}'});
        expect(errorsOf(result), isEmpty, reason: key);
      }
    });
  });
}
