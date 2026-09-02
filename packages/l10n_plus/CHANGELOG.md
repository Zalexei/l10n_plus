# Changelog

## 0.2.0

* `L10nLocaleResolver.resolve` documents its region fallback: with no exact
  match and no bare language, it takes the **first** supported locale sharing
  the language, in the order given. `en_NZ` resolves to `en_AU` over `en_GB`
  because `AU` sorts first, and for no other reason. Behaviour is unchanged and
  now has a test that says so.
* `PluralOperands` documents where a `num` cannot carry what CLDR asks: `1.0`
  and `1` are the same value in Dart, so `v` is 0 for both.

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
