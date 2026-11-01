@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/deferred/app_localizations.g.dart';

/// Runs the `deferred` golden instead of only reading it.
///
/// The golden test proves the imports were written and `dart analyze` proves
/// they type check. Neither proves what an application sees: that reading an
/// unloaded locale gives the fallback rather than throwing, that loading
/// replaces it with the real thing, and that the `const` canonicalization
/// survives the deferred boundary. This is the same files, executed.
///
/// On the VM `loadLibrary` completes without doing any work — there are no
/// chunks to fetch — so what is under test here is the state machine, not the
/// download. The download is measured by `evaluation/bundle_size.py`.
///
/// What an *unloaded* locale reads as is asserted in
/// `deferred_unloaded_test.dart` rather than here, because a loaded library
/// cannot be unloaded: one `load()` anywhere in this file would settle the
/// question for every test after it. A separate suite is a separate isolate,
/// which is the only `tearDown` available for this.
void main() {
  test('loading replaces the fallback with the real translations', () async {
    await AppLocale.ru.load();
    expect(AppLocale.ru.isLoaded, isTrue);

    final t = AppLocalizations.forLocale(AppLocale.ru);
    expect(t.auth.title, 'Войти');
    expect(t.auth.greeting(name: 'Ада'), 'С возвращением, Ада');
    // The Russian conditions, not the English ones reached through a fallback.
    expect(t.wallet.transactions(count: 1), '1 операция');
    expect(t.wallet.transactions(count: 3), '3 операции');
    expect(t.wallet.transactions(count: 11), '11 операций');
    expect(t.wallet.transactions(count: 0), 'Нет операций');
  });

  test('the const graph survives the deferred boundary', () async {
    // The one thing that could have been lost. `const` of a class behind a
    // deferred prefix is a compile error, so the instance is built inside the
    // locale's own library — where it is an ordinary `const` and Dart
    // canonicalizes it. Reading twice gives one object, as it does with the
    // option off.
    await AppLocale.ru.load();
    final a = AppLocalizations.forLocale(AppLocale.ru);
    final b = AppLocalizations.forLocale(AppLocale.ru);
    expect(identical(a, b), isTrue);
    expect(identical(a.wallet, b.wallet), isTrue);
  });

  test('loading twice is not an error and changes nothing', () async {
    await AppLocale.ru.load();
    final first = AppLocalizations.forLocale(AppLocale.ru);
    await AppLocale.ru.load();
    expect(identical(AppLocalizations.forLocale(AppLocale.ru), first), isTrue);
  });

  test('loadAll leaves every locale loaded', () async {
    await AppLocale.loadAll();
    for (final locale in AppLocale.values) {
      expect(locale.isLoaded, isTrue, reason: locale.name);
    }
    expect(AppLocalizations.forLocale(AppLocale.de).auth.title, 'Anmelden');
  });

  test('loading the fallback is a no-op rather than a special case', () async {
    await AppLocale.en.load();
    expect(AppLocale.en.isLoaded, isTrue);
  });
}
