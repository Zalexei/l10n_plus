import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_plus/l10n_plus.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

/// A locale whose load this test finishes by hand.
///
/// `deferred_locales_test.dart` drives the real thing, but a real deferred
/// library loads once and cannot be unloaded, so it cannot answer what
/// happens *while* a load is in flight. That is what this file is for.
final class _Locale implements AppLocaleBase, DeferredAppLocale {
  _Locale(this.tag, {bool loaded = false}) : _loaded = loaded;

  final String tag;
  final _completer = Completer<void>();
  bool _loaded;

  @override
  bool get isLoaded => _loaded;

  @override
  Future<void> load() => _completer.future;

  /// Finishes the load, as the chunk arriving would.
  void arrive() {
    _loaded = true;
    if (!_completer.isCompleted) _completer.complete();
  }

  @override
  L10nLocale get l10nLocale => L10nLocale.parse(tag);
}

final class _Translations implements BaseTranslations {
  const _Translations(this.locale);

  final _Locale locale;

  @override
  L10nLocale get l10nLocale => locale.l10nLocale;
}

void main() {
  late _Locale en;
  late _Locale ru;
  late _Locale de;

  L10nController<_Locale, _Translations> controller() {
    final created = L10nController<_Locale, _Translations>(
      supportedLocales: [en, ru, de],
      fallbackLocale: en,
      initialLocale: en,
      translationsOf: _Translations.new,
    );
    addTearDown(created.dispose);
    return created;
  }

  setUp(() {
    en = _Locale('en', loaded: true);
    ru = _Locale('ru');
    de = _Locale('de');
  });

  test('a later choice wins over a switch that is still loading', () async {
    // `setLocaleAsync` awaited the chunk and then switched unconditionally,
    // so a user who grew tired of waiting and picked another language was
    // moved back to the first one the moment the download landed.
    final subject = controller();
    final pending = subject.setLocaleAsync(ru);

    subject.setLocale(de);
    expect(subject.locale, de);

    ru.arrive();
    await pending;

    expect(subject.locale, de);
  });

  test('a switch that is still loading survives nothing else happening', () {
    // The guard must not swallow the ordinary case.
    final subject = controller();
    final pending = subject.setLocaleAsync(ru);

    ru.arrive();
    return pending.then((_) => expect(subject.locale, ru));
  });

  test('the last of two awaited switches is the one that lands', () async {
    final subject = controller();
    final first = subject.setLocaleAsync(ru);
    final second = subject.setLocaleAsync(de);

    de.arrive();
    await second;
    ru.arrive();
    await first;

    expect(subject.locale, de);
  });

  test('a controller disposed while loading is not notified', () async {
    // `notifyListeners` on a disposed `ChangeNotifier` throws, and a settings
    // screen popped during the download is exactly when that happens.
    final subject = L10nController<_Locale, _Translations>(
      supportedLocales: [en, ru, de],
      fallbackLocale: en,
      initialLocale: en,
      translationsOf: _Translations.new,
    );
    final pending = subject.setLocaleAsync(ru);

    subject.dispose();
    ru.arrive();

    await expectLater(pending, completes);
  });
}
