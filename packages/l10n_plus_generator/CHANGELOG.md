# Changelog

## 0.1.0

First release.

**Formats.** JSON with nested keys, ARB (`@@locale`, `@key` metadata, dotted
keys) and YAML. A locale may be spread over any number of files, in any mix of
formats; `file_pattern` says where the locale sits in the path and whether the
file name becomes a namespace.

**ICU.** `{placeholder}`, `plural` with `=N`, CLDR categories and `offset:`,
`select`, `selectordinal`, `#`, arbitrary nesting and apostrophe quoting. CLDR
plural and ordinal rules are inlined per locale from a curated table; an
unknown language is reported rather than given English rules.

**Numbers and dates.** Named styles and `DateFormat` skeletons, explicit
currency codes (`{n, number, currency:USD}`), `simpleCurrency`, and ARB's
`symbol` and `decimalDigits`. `package:intl` is imported only by generated
files that actually format something, and `format_plural_numbers` decides
whether `#` is formatted.

**Validation.** Every locale is checked against the base locale, which is the
API contract. `fill_missing_from_base` lets a locale be incomplete, rendering
untranslated messages exactly as the base locale renders them.

**Output.** A typed nested API over a `const` object graph, deterministic byte
for byte, `dart_style` formatted, and analyzer-clean in a consumer's project.
`file_per_locale` splits it into one `part` per locale.

**CLI.** `generate`, `analyze` and `unused`, all with diagnostics carrying
file, line, column, key, and what was expected versus found.
