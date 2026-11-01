@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/deferred/app_localizations.g.dart';

/// What a locale reads as before anything has loaded it.
///
/// A suite of its own because a loaded library cannot be unloaded: in a file
/// that also loads one, every test after the first would be asserting about a
/// loaded locale whatever its name said. `test` runs each suite in its own
/// isolate, which is the only `tearDown` deferred loading allows — and the
/// limitation is the feature's, not the test's.
void main() {
  test('an unloaded locale reads as the fallback, and does not throw', () {
    // The decision this feature turns on. A `null` or a throw here would put
    // a run time hazard in the middle of the API this library exists to make
    // safe; falling back is what an *unsupported* locale has always done, so
    // the behaviour is one the library already had with a different cause.
    expect(AppLocale.ru.isLoaded, isFalse);
    expect(AppLocale.de.isLoaded, isFalse);
    expect(AppLocalizations.forLocale(AppLocale.ru).auth.title, 'Log in');
    expect(
      AppLocalizations.forLocale(AppLocale.ru).wallet.transactions(count: 2),
      '2 payments',
    );
    // Including through the resolver, which is the path an application that
    // reads the system locale takes.
    expect(AppLocalizations.of(const L10nLocale('ru')).auth.title, 'Log in');
  });

  test('the fallback locale is loaded from the start', () {
    expect(AppLocale.en.isLoaded, isTrue);
    expect(AppLocalizations.forLocale(AppLocale.en).auth.title, 'Log in');
  });
}
