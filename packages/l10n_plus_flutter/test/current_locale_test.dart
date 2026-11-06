import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The generator's `overrides` golden, imported by path for the reason
// `overrides_test.dart` gives: this package is the one that can compile the
// glue, and the file under test is then byte for byte the generated one.
import '../../l10n_plus_generator/test/goldens/overrides/app_localizations.g.dart';
import '../../l10n_plus_generator/test/goldens/overrides/app_localizations_flutter.g.dart';

/// `AppLocalizations.current` kept in step by the generated factory.
void main() {
  tearDown(
    () => AppLocalizations.currentLocale = AppLocalizations.fallbackLocale,
  );

  AppLocalizationsController create({
    AppLocale? locale,
    List<Locale> systemLocales = const [],
  }) {
    final controller = createAppLocalizationsController(
      locale: locale,
      systemLocales: systemLocales,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('a new controller makes its locale current', () {
    create(locale: AppLocale.ru);
    expect(AppLocalizations.currentLocale, AppLocale.ru);
    expect(AppLocalizations.current.appLocale, AppLocale.ru);
  });

  test('the system locale it resolved is current from the start', () {
    create(systemLocales: const [Locale('ru', 'RU')]);
    expect(AppLocalizations.currentLocale, AppLocale.ru);
  });

  test('setLocale and useSystemLocale move current with the screen', () {
    final controller = create(locale: AppLocale.en);

    controller.setLocale(AppLocale.ru);
    expect(AppLocalizations.currentLocale, AppLocale.ru);

    controller.useSystemLocale(const [L10nLocale('en')]);
    expect(AppLocalizations.currentLocale, AppLocale.en);
  });

  test('a system locale change reaches current', () {
    final controller = create(systemLocales: const [Locale('en')]);
    controller.handleSystemLocalesChanged(const [L10nLocale('ru')]);
    expect(AppLocalizations.currentLocale, AppLocale.ru);
  });

  test('with two controllers, the one that changed last wins', () {
    final first = create(locale: AppLocale.en);
    final second = create(locale: AppLocale.ru);
    expect(AppLocalizations.currentLocale, AppLocale.ru);

    second.setLocale(AppLocale.en);
    first.setLocale(AppLocale.ru);
    expect(AppLocalizations.currentLocale, AppLocale.ru);
  });
}
