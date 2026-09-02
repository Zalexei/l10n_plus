# l10n_plus_generator

Reads JSON, ARB and YAML translations and writes a typed Dart API for them.
A `dev_dependency`: nothing here ships in an application.

```bash
dart run l10n_plus_generator generate   # write the generated files
dart run l10n_plus_generator analyze    # validate only, non-zero on error
dart run l10n_plus_generator unused     # report translations nothing uses
```

What it does:

* Full ICU: `{placeholder}`, `plural` (`=N`, categories, `offset:`),
  `select`, `selectordinal`, `#`, arbitrary nesting, apostrophe quoting.
* CLDR plural rules inlined per locale, so no rule table reaches your app.
* Numbers and dates through `package:intl`, imported **only** by generated
  files that actually format something — including explicit currency codes,
  symbols and fraction digits.
* Cross-locale validation against the base locale, which is the API contract.
* Diagnostics with file, line, column, key, what was expected and what was
  found. Never "Invalid message."

Configuration lives in `l10n_plus.yaml`. Translations may be split across many
files, and output across one file per locale.

Full guide, every option and the design notes: **the repository README and `docs/architecture.md`.**
