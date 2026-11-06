@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/current/app_localizations.g.dart';

/// Runs `AppLocalizations.current` in the `current` golden instead of
/// reading it.
void main() {
  tearDown(AppLocalizations.resetCurrent);

  final enT = AppLocalizations.forLocale(AppLocale.en);
  final ruT = AppLocalizations.forLocale(AppLocale.ru);

  test('reads the fallback locale until something is installed', () {
    expect(AppLocalizations.currentCell.locale, isNull);
    expect(AppLocalizations.currentLocale, AppLocalizations.fallbackLocale);
    expect(AppLocalizations.current.auth.login.title, enT.auth.login.title);
  });

  test('setCurrentLocale moves it, resetCurrent puts it back', () {
    AppLocalizations.setCurrentLocale(AppLocale.ru);
    expect(AppLocalizations.current.appLocale, AppLocale.ru);
    expect(t.auth.login.title, ruT.auth.login.title);

    AppLocalizations.resetCurrent();
    expect(AppLocalizations.currentLocale, AppLocale.en);
  });

  test('a string read from it is a snapshot', () {
    // The behaviour the documentation warns about, pinned so that nobody
    // "fixes" it into something that only looks live.
    AppLocalizations.setCurrentLocale(AppLocale.ru);
    final stored = t.auth.login.title;
    AppLocalizations.setCurrentLocale(AppLocale.en);
    expect(stored, ruT.auth.login.title);
    expect(stored, isNot(t.auth.login.title));
  });
}
