import 'dart:ui' show TextDirection;

import 'package:flutter/foundation.dart';
import 'package:l10n_plus/l10n_plus.dart';

import 'flutter_locale.dart';

/// Holds the active locale and notifies listeners when it changes.
///
/// This is a plain [ChangeNotifier], so the library never forces a state
/// management package on the app. [L10nScope] listens to it; anything else can
/// listen to it too.
final class L10nController<L extends AppLocaleBase, T extends BaseTranslations>
    extends ChangeNotifier {
  /// Creates a controller.
  ///
  /// [initialLocale] wins when given; otherwise [systemLocales] are resolved
  /// against [supportedLocales], falling back to [fallbackLocale].
  L10nController({
    required this.supportedLocales,
    required this.fallbackLocale,
    required T Function(L locale) translationsOf,
    L? initialLocale,
    List<L10nLocale> systemLocales = const [],
  }) : _translationsOf = translationsOf,
       _followSystem = initialLocale == null {
    _locale = initialLocale ?? _resolveSystem(systemLocales);
    // Subscribed whether or not the project generates override lookups: the
    // store is empty in a project that does not, so this costs one callback
    // that is never called. Subscribing is what makes an override repaint the
    // screen instead of showing up on the next one that happens to rebuild —
    // the reason the roadmap's objection to global state does not apply here.
    L10nOverrides.addListener(_handleOverridesChanged);
    // The initial locale may be one whose translations are a deferred chunk,
    // which is the ordinary case for a web app launched in a language that is
    // not the fallback. Nothing has to be awaited for the first frame to
    // render — it renders the fallback — and this repaints it when the real
    // one arrives.
    _load(_locale);
  }

  /// Locales the app has translations for.
  final List<L> supportedLocales;

  /// Locale used when nothing matches.
  final L fallbackLocale;

  final T Function(L locale) _translationsOf;

  late L _locale;
  bool _followSystem;
  bool _disposed = false;

  /// The active locale.
  L get locale => _locale;

  /// Translations of the active locale.
  T get translations => _translationsOf(_locale);

  /// Which way the active locale's text runs.
  ///
  /// Changes with [locale] and notifies the same listeners, so a `MaterialApp`
  /// wrapped in a `Directionality` built from this flips the whole layout when
  /// the user switches to Arabic or Hebrew. Exposed here so that an app reads
  /// the direction from the thing that already knows the locale, instead of
  /// keeping a language list of its own next to this one.
  ///
  /// This is the direction of the *locale*, which is the correct default for a
  /// screen. It says nothing about an individual interpolated value: a Latin
  /// name inside an Arabic sentence still needs bidi isolation, which is a
  /// property of the text and not of the locale.
  TextDirection get textDirection => _locale.l10nLocale.textDirection;

  /// Whether the controller tracks the operating system locale.
  bool get followsSystemLocale => _followSystem;

  /// Switches to [locale] and stops following the system locale.
  ///
  /// Synchronous even when the locale's translations are a deferred chunk:
  /// the switch happens now, the chunk is requested, and the screen repaints
  /// when it arrives. Until then the locale renders the fallback's text, the
  /// same thing an unsupported locale renders. [setLocaleAsync] is the version
  /// that waits, for a caller that would rather not show that frame.
  void setLocale(L locale) {
    _followSystem = false;
    _set(locale);
  }

  /// Switches to [locale] once its translations are in memory.
  ///
  /// With `deferred_locales` off there is nothing to load and this is
  /// [setLocale] with a future around it. With it on, awaiting this is how a
  /// caller avoids the frame in which the new locale still reads as the
  /// fallback — a settings screen that pops a route on completion, say.
  ///
  /// Loading does not depend on this: [setLocale] starts it too. This only
  /// decides whether the switch is visible before or after the download.
  Future<void> setLocaleAsync(L locale) async {
    // Typed as `Object` so the test promotes to `DeferredAppLocale` itself:
    // `L`'s bound is `AppLocaleBase`, and promoting a type variable to an
    // unrelated interface gives an intersection whose members the analyzer
    // will not resolve.
    final Object candidate = locale;
    if (candidate is DeferredAppLocale) await candidate.load();
    setLocale(locale);
  }

  /// Follows the operating system locale again.
  ///
  /// [systemLocales] is the platform's preferred locale list, most preferred
  /// first. [L10nScope] keeps it up to date automatically.
  void useSystemLocale(List<L10nLocale> systemLocales) {
    _followSystem = true;
    _set(_resolveSystem(systemLocales));
  }

  /// Called by [L10nScope] when the platform locales change.
  void handleSystemLocalesChanged(List<L10nLocale> systemLocales) {
    if (!_followSystem) return;
    _set(_resolveSystem(systemLocales));
  }

  /// Removes the overrides of [locale], or of every locale, and repaints.
  ///
  /// There is no `installOverrides` here to match it. Installing is the
  /// generated `AppLocale.ru.installOverrides(bundle)`, because that is where
  /// the locale's own fingerprint is a compile time constant and a bundle
  /// stamped for another build can be refused. A controller method would have
  /// had to take the fingerprint as an argument to do the same thing, which
  /// is longer than the call it was sugar for.
  ///
  /// Installing through the generated method still repaints: the controller
  /// subscribes to the store itself, so who calls it makes no difference.
  ///
  /// **No fetching, either way.** Downloading the bundle, caching it,
  /// authenticating the request and deciding when to trust it are the
  /// application's, because they are its policy and because this library has
  /// no dependencies to spend on them. Validate — and stamp — the bundle
  /// before it ships:
  ///
  /// ```sh
  /// dart run l10n_plus_generator check-overrides --from=overrides_en.json --stamp
  /// ```
  ///
  /// [setLocale] stays synchronous. The roadmap expected *this* feature to
  /// make it asynchronous; it does not, because the fetch happens before the
  /// install, in the application's own code, and the install itself is a map
  /// assignment. `deferred_locales` is the feature that did need an
  /// asynchronous companion, and it got [setLocaleAsync] rather than a second
  /// meaning for this one.
  void clearOverrides([L10nLocale? locale]) => L10nOverrides.clear(locale);

  /// Repaints every reader when the override store changes.
  ///
  /// Unconditional: the store is told which locale changed and this is not,
  /// and a rebuild of the screens reading translations is cheaper than the
  /// bookkeeping that would avoid it.
  void _handleOverridesChanged() => notifyListeners();

  @override
  void dispose() {
    // Before `super.dispose()`: a notification arriving after disposal would
    // throw, and installing a bundle while a screen is being torn down is
    // exactly when that happens.
    _disposed = true;
    L10nOverrides.removeListener(_handleOverridesChanged);
    super.dispose();
  }

  void _set(L locale) {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    _load(locale);
  }

  /// Starts loading [locale]'s translations, repainting when they arrive.
  ///
  /// Nothing waits on this, which is what keeps [setLocale] synchronous. Two
  /// guards on the way back: a controller disposed in the meantime would throw
  /// if notified, and a locale switched away from again should not repaint a
  /// screen that has moved on.
  void _load(L locale) {
    final Object candidate = locale;
    if (candidate is! DeferredAppLocale || candidate.isLoaded) return;
    candidate.load().then((_) {
      if (_disposed || _locale != locale) return;
      notifyListeners();
    });
  }

  L _resolveSystem(List<L10nLocale> systemLocales) {
    for (final candidate in systemLocales) {
      for (final supported in supportedLocales) {
        if (supported.l10nLocale == candidate) return supported;
      }
    }
    return L10nLocaleResolver.resolve(
      requested: systemLocales.firstOrNull,
      supported: supportedLocales,
      fallback: fallbackLocale,
    );
  }
}
