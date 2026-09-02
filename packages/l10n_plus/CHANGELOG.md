# Changelog

## 0.1.0

First release. The runtime half of `l10n_plus`, with zero dependencies.

* `L10nLocale`: a locale value type with canonical parsing of `en`, `pt_BR`,
  `zh-Hant-TW` and friends.
* `L10nLocaleResolver`: the `locale → language → fallback` chain used by
  generated `AppLocalizations.of`. With no exact match and no bare language it
  takes the **first** supported locale sharing the language, in the order
  given — `en_NZ` resolves to `en_AU` over `en_GB` because `AU` sorts first,
  and for no other reason. Arbitrary, stable, and documented rather than
  dressed up as a preference.
* `PluralOperands`: the CLDR operands `n, i, v, w, f, t`, computed from a
  `num`. The rules themselves are inlined into generated code, so no rule
  table ships in an application. Note that a `num` cannot carry what CLDR
  calls `v`: `1.0` and `1` are the same value in Dart, so both have no visible
  fraction digits here.
* `BaseTranslations` and `AppLocaleBase`, the interfaces generated code
  implements.
