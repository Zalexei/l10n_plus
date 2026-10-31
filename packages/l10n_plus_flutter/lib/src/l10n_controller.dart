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
  }

  /// Locales the app has translations for.
  final List<L> supportedLocales;

  /// Locale used when nothing matches.
  final L fallbackLocale;

  final T Function(L locale) _translationsOf;

  late L _locale;
  bool _followSystem;

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
  void setLocale(L locale) {
    _followSystem = false;
    _set(locale);
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

  void _set(L locale) {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
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
