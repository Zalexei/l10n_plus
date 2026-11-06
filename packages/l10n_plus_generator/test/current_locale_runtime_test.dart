@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/json/app_localizations.g.dart';

/// Runs `AppLocalizations.current` in the `json` golden instead of reading it.
void main() {
  tearDown(
    () => AppLocalizations.currentLocale = AppLocalizations.fallbackLocale,
  );

  test('reads the fallback locale until something sets one', () {
    expect(AppLocalizations.currentLocale, AppLocalizations.fallbackLocale);
    expect(
      AppLocalizations.current.auth.login.title,
      AppLocalizations.forLocale(
        AppLocalizations.fallbackLocale,
      ).auth.login.title,
    );
  });

  test('follows currentLocale on every read', () {
    AppLocalizations.currentLocale = AppLocale.ru;
    expect(AppLocalizations.current.appLocale, AppLocale.ru);
    expect(
      AppLocalizations.current.auth.login.title,
      AppLocalizations.forLocale(AppLocale.ru).auth.login.title,
    );

    AppLocalizations.currentLocale = AppLocale.en;
    expect(AppLocalizations.current.appLocale, AppLocale.en);
  });

  test('a string read from it is a snapshot', () {
    // The behaviour the documentation warns about, pinned so that nobody
    // "fixes" it into something that only looks live.
    AppLocalizations.currentLocale = AppLocale.ru;
    final stored = AppLocalizations.current.auth.login.title;
    AppLocalizations.currentLocale = AppLocale.en;
    expect(stored, AppLocalizations.forLocale(AppLocale.ru).auth.login.title);
    expect(stored, isNot(AppLocalizations.current.auth.login.title));
  });
}
