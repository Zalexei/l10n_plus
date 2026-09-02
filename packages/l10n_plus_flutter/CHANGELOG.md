# Changelog

## 0.1.0

First release. The Flutter edge of `l10n_plus`.

* `L10nController`: the active locale, with a synchronous `setLocale` and
  optional system-locale following.
* `L10nScope`: an `InheritedNotifier` that rebuilds dependents on a change,
  with a diagnostic that explains what to do when it is missing.
* `Locale` interop between Flutter and `L10nLocale`.
* Supports the generated `context.l10n` extension, named by
  `context_extension` in the configuration.
