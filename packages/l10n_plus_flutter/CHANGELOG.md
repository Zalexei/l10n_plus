# Changelog

## 0.1.0

First release. The Flutter edge of `l10n_plus`.

* `L10nController`: the active locale, with a synchronous `setLocale` and
  optional system-locale following. The generated factory hands it the
  platform's locales, so an app opens in the device's language on the first
  frame rather than waiting for a `didChangeLocales` that never comes.
* `L10nScope`: an `InheritedNotifier` that rebuilds dependents on a change,
  with a diagnostic that explains what to do when it is missing.
* `Locale` interop between Flutter and `L10nLocale`.
* Supports the generated `context.l10n` extension, named by
  `context_extension` in the configuration.
* `L10nController(current: ...)`: with `global_translations: true` the
  generated factory passes the cell behind `AppLocalizations.current`, and the
  controller installs its locale there before notifying and releases it on
  `dispose`.
