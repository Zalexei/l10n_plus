# Changelog

## 0.1.0

First release. The runtime half of `l10n_plus`, with zero dependencies.

* `L10nLocale`: a locale value type with canonical parsing of `en`, `pt_BR`,
  `zh-Hant-TW` and friends.
* `L10nLocaleResolver`: the `locale → language → fallback` chain used by
  generated `AppLocalizations.of`.
* `PluralOperands`: the CLDR operands `n, i, v, w, f, t`, computed from a
  `num`. The rules themselves are inlined into generated code, so no rule
  table ships in an application.
* `BaseTranslations` and `AppLocaleBase`, the interfaces generated code
  implements.
