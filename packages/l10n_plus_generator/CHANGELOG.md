# Changelog

## 0.1.0

First release.

**Formats.** JSON with nested keys, ARB (`@@locale`, `@key` metadata, dotted
keys) and YAML. A locale may be spread over any number of files, in any mix of
formats; `file_pattern` says where the locale sits in the path and whether the
file name becomes a namespace.

**ICU.** `{placeholder}`, `plural` with `=N`, CLDR categories and `offset:`,
`select`, `selectordinal`, `#`, arbitrary nesting and apostrophe quoting. An
explicit `=N` branch counts as covering a category the language defines as
that one value, which is the shape an ARB bundle exported from `gen_l10n` has.

**Plural rules.** Every language CLDR publishes: 222 cardinal and 107 ordinal,
compiled from CLDR 48 by `tool/update_cldr_plural_rules.dart` and inlined per
locale, so no rule table reaches an application. Checked against CLDR's own
`@integer` and `@decimal` samples and, where it has them, against
`package:intl` — two oracles, because each catches what the other misses. A
language CLDR does not know is reported rather than given English rules.

**Numbers and dates.** Named styles and `DateFormat` skeletons, explicit
currency codes (`{n, number, currency:USD}`), the `currency`/`simpleCurrency`
and `compactCurrency`/`compactSimpleCurrency` pairs, `decimalPercentPattern`,
and ARB's `symbol` and `decimalDigits`. The names `gen_l10n` writes —
`decimalPattern`, `percentPattern`, `scientificPattern` — are accepted as
spellings of the same styles, so an exported bundle needs no edits.
`package:intl` is imported only by generated files that actually format
something, and `format_plural_numbers` decides whether `#` is formatted. A
date formatted before `initialize<Class>Formatting()` has been awaited throws
an error naming that call.

**Validation.** Every locale is checked against the base locale, which is the
API contract. `fill_missing_from_base` lets a locale be incomplete, rendering
untranslated messages exactly as the base locale renders them;
`extra_keys: warn` lets a translation outlive the key it was written for.
`ignore_diagnostics` turns off warning codes a project has decided about —
warnings only, and the suppressed count is always printed.

**Output.** A typed nested API over a `const` object graph, deterministic byte
for byte, `dart_style` formatted, and analyzer-clean in a consumer's project.
Every generated top level name is claimed in one registry, so two keys that
would produce one class name are reported rather than emitted.
`file_per_locale` splits the library into one `part` per locale.

**CLI.** `generate`, `analyze` and `unused`, all with diagnostics carrying
file, line, column, key, and what was expected versus found.
