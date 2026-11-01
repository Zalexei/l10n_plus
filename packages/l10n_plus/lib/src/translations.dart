import 'locale.dart';

/// Implemented by the generated `AppLocale` enum.
///
/// Lets the runtime resolve locales without knowing the generated type.
abstract interface class AppLocaleBase {
  /// The locale this enum value stands for.
  L10nLocale get l10nLocale;
}

/// Implemented by a generated locale enum whose translations load on demand.
///
/// Only with `deferred_locales: true`. Each locale but the fallback is then a
/// separate Dart library behind a deferred import, so a web build splits it
/// into a chunk of its own and an application downloads the languages it
/// actually shows.
///
/// A locale that is not loaded yet is not an error and never throws: reading
/// its translations gives the fallback locale's, which is what reading an
/// *unsupported* locale has always given. Loading is what stops it falling
/// back. `L10nController` calls [load] itself when the locale changes and
/// repaints when it arrives, so an application that switches locales through
/// the controller needs none of this; an application that reads
/// `AppLocalizations.forLocale` directly is the one that has to await it.
abstract interface class DeferredAppLocale {
  /// Whether this locale's translations are in memory.
  ///
  /// Always true for the fallback locale, which is never deferred: something
  /// has to be renderable before anything has loaded.
  bool get isLoaded;

  /// Loads this locale's translations.
  ///
  /// Completes immediately when they are already in memory. Safe to call
  /// again and from several places at once: the underlying `loadLibrary` is
  /// idempotent and returns the same future.
  Future<void> load();
}

/// Implemented by the generated root translations class of every locale.
abstract interface class BaseTranslations {
  /// The locale these translations were generated for.
  L10nLocale get l10nLocale;
}
