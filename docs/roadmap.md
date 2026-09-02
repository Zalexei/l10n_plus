# Roadmap

## Milestone 0 — vertical slice (done)

Everything below works end to end today.

* JSON source format, nested namespaces
* span-aware JSON parser
* ICU parser: literals, `{placeholder}`, `plural` (`=N` and categories), `select`,
  `#`, arbitrary nesting, apostrophe quoting
* argument inference: `String`, `num`, generated select enums
* CLDR plural rules for 30 languages, inlined per locale at generation time
* cross-locale validation against the base locale
* Dart code generation: nested typed API, `const` object graph, `dart_style`
  formatted, deterministic
* Flutter glue: `L10nScope`, `L10nController`, `context.l10n`, locale switching,
  system-locale following
* `generate` and `analyze` CLI commands, non-zero exit for CI
* 98 unit/golden tests plus 5 widget/integration tests in the example app

## Milestone 1 — ARB and metadata (done)

* `ArbSourceParser`: `@@locale`, `@key` metadata, dotted keys expanded into
  namespaces, flat-format diagnostics
* `MessageMetadata` on the structure layer: description and placeholder
  declarations, filled by ARB and empty for JSON
* declared placeholder types refine the generated signature (`int`, `num`,
  `double`, `Object`, `String`); `DateTime` is rejected with a diagnostic
* descriptions, argument descriptions and examples become DartDoc
* ARB and JSON locales validate against each other in one project
* golden fixtures for both formats, proving they generate the same API shape

## Milestone 2 — numbers and dates (done)

* `{n, number}`, `{d, date}`, `{t, time}` with named styles and `DateFormat`
  skeletons, validated against an allowlist
* ARB `"format"` drives formatting for placeholders written plainly, which is
  what a `gen_l10n` bundle looks like
* formatters emitted as lazily initialized top level finals, one per locale and
  style; `package:intl` imported only when something actually formats
* `missing_intl_dependency` diagnostic, read from the project's `pubspec.yaml`
* generated `initialize<Class>Formatting()` for ICU date symbols
* argument conflicts compare Dart type families, so `{d, date}` and `{d, time}`
  coexist
* runtime tests assert real formatted output in English and Russian

## Milestone 3 — full ICU and build_runner (done)

* `{n, selectordinal, ...}` on a curated CLDR **ordinal** rule table, separate
  from the cardinal one; unknown languages produce `unknown_ordinal_language`
* plural `offset:` with ICU semantics — `=N` matches the original value, `#`
  and the category rules see the adjusted one
* `plural_type_mismatch` when locales disagree on cardinal versus ordinal
* `l10n_plus_builder`: a `build_runner` adapter over the same generator API,
  with the pipeline split into `generate(inputs)` (no IO) and `run()` (dart:io)
* runtime tests assert real ordinal output (1st, 2nd, 3rd, 11th, 21st, 113th)
  and offset plurals in English and Russian

## Milestone 4 — number rendering (done)

* explicit currency codes in messages, `{amount, number, currency:USD}`, and in
  ARB metadata, `"optionalParameters": {"name": "USD"}` — the spelling
  `gen_l10n` writes, so an exported bundle needs no edits
* the code is validated as three upper case letters at both entry points; a
  code on a non currency style, on a plural or select argument, or disagreeing
  with the one in the message is an error
* an ICU number skeleton (`::currency/USD`) is met with a diagnostic naming the
  supported spelling instead of "unknown style"
* the code is part of the generated formatter's name, so several currencies
  coexist in one locale
* `format_plural_numbers: false` (default) makes ICU `#` formatting a project
  choice; when on, `#` renders through the locale's `NumberFormat` in `plural`
  and `selectordinal`, before and after `offset:`
* goldens cover both settings: the JSON fixture off and importing no `intl`,
  the ARB fixture on
* runtime tests in the example assert real `intl` output — `USD` rendered in a
  Russian locale, and `#` grouped as `1,500` / `1 500`

## Milestone 5 — currency completeness (done)

* `simpleCurrency` as a second number style, so code versus symbol is a per
  message choice: `{amount, number, currency:USD}` gives `USD1,234.50`,
  `{amount, number, simpleCurrency:USD}` gives `$1,234.50`
* ARB `optionalParameters.symbol` and `.decimalDigits` honoured, validated
  (`0..20`, `2` or `"2"`) and escaped into the generated literal
* `customPattern` still refused, on purpose: it can only fail at run time
* every distinguishing option is part of the formatter's field name, so two
  currencies or two digit counts in one locale never collapse onto one final
* a declared numeric type survives a declared format — `{"type": "double",
  "format": "currency"}` now generates `double`, matching what writing the
  format in the message has always produced

## Milestone 6 — per locale currency settings (done)

* a non base bundle's `optionalParameters` now shape *its own* rendering,
  merged over the base's, so a Russian file quotes roubles without kopecks
  while English quotes dollars with cents
* `currency_options_mismatch` warns only when two locales name explicit and
  different currency codes; differing digits or symbols are the intended use
* `symbol` restricted to the `currency` style — `NumberFormat.simpleCurrency`
  has no `symbol:` parameter, so declaring one used to generate a file that
  did not compile. Found by running the example, not by a golden.
* the example is now a mixed project: `en.json` base plus `app_ru.arb`, which
  is what makes `symbol` and `decimalDigits` execute in a real app

## Milestone 7 — the generated code is type checked (done)

* `intl` added as a **dev** dependency of the generator, and
  `test/goldens/**` un-excluded from the analyzer, so `dart analyze` resolves
  generated output against the real `package:intl`
* `test/goldens/formats/` covers the whole formatter surface, with its input
  derived from `IntlFormatters` so new styles are covered automatically
* found and fixed two latent bugs that emitted uncompilable code:
  `NumberFormat.integer` does not exist (ICU `integer` is now
  `decimalPatternDigits(decimalDigits: 0)`, since Milestone 2), and
  `simpleCurrency` has no `symbol:` parameter
* `integer` also exercised in the example, which is what shows it rounds and
  still groups — analysis alone would not have

## Milestone 8 — per locale styles (done)

* a non base bundle may declare its own `format`, inheriting the currency and
  the fraction digits and changing only how the amount is spelled; the
  argument's *kind* is never overridden, so the signature stays shared
* one precedence rule everywhere: the message beats the metadata, then the
  locale's declaration, then the base's
* formatting cannot be introduced by one locale alone — that would change the
  generated type — and says so with `unexpected_placeholder_format`
* `time` no longer accepts date skeletons: `{t, time, yMMMd}` rendered a date
  and dropped the time. `date` stays permissive, because `{d, date, jm}` has
  always worked and renders what it says.

## Milestone 9 — the goldens are executed (done)

* `goldens_runtime_test.dart` imports the formatter surface golden as a
  library and asserts real `intl` output — no second app, no Flutter, and the
  file executed is byte for byte the file analyzed
* the surface fixture gained a second locale, so the per locale style override
  is now type checked *and* run: the base declares `currency` with zero
  fraction digits, the Russian bundle declares only `"format":
  "simpleCurrency"` and inherits the rest
* verified the guard by regression: deleting `decimalDigits` from the emitted
  argument list still compiles and still analyzes clean, and the runtime test
  catches `USD1,234.56` where `USD1,235` was asked for

## Milestone 10 — several input files per locale (done)

* `file_pattern` with `{locale}`, `*` and `**`, matched against the path
  relative to the input directory; discovery is now recursive
* a locale may be spread over any number of files, in any supported format;
  they merge, and a file name reaches nothing in the generated API
* groups merge, leaves collide: `duplicate_key` and `conflicting_key_kind`
  name both files, replacing the old `duplicate_locale_file`, which could only
  say that two files existed
* the same mechanism resolves the `app_en` ambiguity: `file_pattern:
  "app_{locale}"`
* a configured pattern is a claim, so `locale_pattern_mismatch` reports a file
  whose `@@locale` disagrees with its path; the default claims nothing
* `declaresLocale` on the parser seam, so a format that cannot name its own
  locale is skipped before it is asked to read a path that does not match
* a `split` golden fixture: three files per locale, two formats, one API

## Milestone 11 — one generated file per locale (done)

* `file_per_locale` splits the library into a shared file and one `part` per
  locale, each carrying the formatters only it uses
* `part` rather than separate libraries, so the import an application writes
  is unchanged and the Flutter glue is byte for byte identical either way
* `build_runner` outputs stay declared in `build.yaml`, which is its rule and
  not something an adapter can hide; the builder names any file it could not
  write, with the block to paste
* fixed a defect from the previous milestone: the builder globbed
  `translations/*`, which does not cross directories, so a locale in its own
  directory was invisible to `build_runner`
* the example turns it on, which is where Flutter actually compiles the parts

## Milestone 12 — YAML (done)

* `YamlSourceParser` over `package:yaml`, which was already a dependency and
  is span aware; `.yaml` and `.yml`
* implicit typing handled as YAML 1.2 really behaves, not as remembered:
  `yes`/`no`/`on`/`off` stay strings, `true`/`null`/`~`/numbers do not and are
  reported by what they became
* content offsets resolved for plain and simply quoted scalars, so ICU
  diagnostics point inside the message; anything folded or escaped falls back
  to the whole value rather than to a wrong position
* the `yaml` golden fixture is the `json` fixture transcribed, and its output
  is asserted byte for byte identical — two formats in, one API out
* no metadata: a nested document has no natural place for ARB's `@key`, and
  inventing a convention nobody writes would be guessing

## Milestone 13 — the file name may be the namespace (done)

* `{namespace}` beside `*`: the capture becomes a namespace the file's keys go
  under, so `auth_en.json` holds `{"login": ...}` and generates `t.auth.login`
* dots nest, so `wallet.settings_en.json` gives `t.wallet.settings`
* `*` kept, because an ARB export already has fully qualified keys and
  prefixing would produce `auth.auth.login.title`
* nesting happens before merging, so every rule about several files of one
  locale applies unchanged; the `split` fixture was converted from `*` to
  `{namespace}` and its goldens did not change by a byte

## Milestone 14 — unused keys (done)

* `dart run l10n_plus_generator unused` reports base locale messages no Dart
  source refers to, with the key's span and the member it looked for
* a text scan for `.name`, not an `analyzer` pass: exact resolution would put
  the heaviest package in the ecosystem into every consumer's dev
  dependencies, to answer a question that is advisory. The scan errs toward
  "used", so it never calls a live translation dead
* the output directory, `.dart_tool` and `build` are excluded — generated code
  declares the very names being searched for
* not in the `build_runner` adapter after all: the generated file lives in
  `lib/`, so a builder scanning `lib/**` would read its own output and every
  code edit would invalidate the translations

## Milestone 15 — benchmarks (done)

* `example/benchmark/l10n_benchmark.dart`, measured against the runtime map
  the design rejected, so that trade-off is a number rather than a claim
* the first run measured nothing: with constant arguments the JIT hoisted the
  call out of the loop and interpolation "cost" 1.7 ns. Cycling the inputs
  put it at 20.5 ns, which is the real figure
* a test runs every case once, so the benchmark cannot rot unnoticed; no
  timing is asserted, because a threshold that fails on a slow CI box teaches
  people to ignore it

## Milestone 16 — untranslated keys (done)

* `fill_missing_from_base: true` turns a missing key from an error into a
  warning and generates the message from the base locale
* the whole message falls back, rules and formatting included — English text
  under Russian plural rules would render "2 card", which looks deliberate in
  a way an untranslated string does not
* the generated member is marked as untranslated in its doc comment
* it excuses nothing else: `extra_key`, argument mismatches and a missing base
  locale stay errors, because none of them can be filled in from anywhere
* the `fill_missing` golden fixture type checks the fallback paths

## Milestone 17 — publishable packages (done)

* MIT `LICENSE` in the repository root and in each of the four packages
* a `README.md` and `CHANGELOG.md` per package, because pub.dev shows the
  package's own, not the repository's
* two descriptions lengthened past pub.dev's 60 character floor
* `.pubignore` in the generator excludes `test/`: the goldens are generated
  Flutter code and import `flutter` and `l10n_plus_flutter`, which the package
  deliberately does not depend on, so publishing them made pub report imports
  it could not resolve. Archive went from unresolvable to 58 KB.
* `publish_to: none` stays, on purpose: a name on pub.dev is taken by the
  first publish and taken forever
* still open: `repository:` in each pubspec, which needs the actual URL

## Milestone 18 — cold start audit (done)

Built a project from scratch and made the mistakes a newcomer makes.

* Cold start is three files and one command.
* `missing_base_locale` was the weak one: a file called `app_en.json` was
  answered with "Found: app_EN" and nothing else. It now lists each file with
  the locale it parsed as, and works out the `file_pattern` that would have
  matched.
* The rest held up: ICU errors, `extra_key` and `missing_intl_dependency` all
  name the place, the problem and the fix.

## Milestone 19 — evaluated by building applications (done)

Four applications outside the workspace, under `evaluation/`, built and run:
a server side Dart statement renderer with several currencies, a plural and
select heavy catalogue in five languages with five different plural systems,
an 810 message Flutter app over nine feature namespaces with `file_per_locale`
and a partial locale, and an unedited TMS style ARB bundle. Findings and the
evidence for each are in `evaluation/REPORT.md`.

* **The CLDR cardinal table is now differentially tested against
  `package:intl`.** `test/plural_matrix_test.dart` derives one message per
  supported language from the table itself and writes a golden;
  `test/plural_matrix_runtime_test.dart` executes that golden and compares
  every branch against `Intl.pluralLogic(..., useExplicitNumberCases: false)`
  over ~90 samples. `intl` carries its own copy of the CLDR rules, generated
  from ICU data, so it is a genuine second opinion rather than a restatement.
* It found four wrong rules, each shipped and each plausible looking:
  `ar` matched non integers against a range (`3.5` was `few`; UTS #35 ranges
  match integers only), `he` was missing `one`'s `i = 0 and v != 0` clause,
  `ro`'s `few` range started at 2 rather than 1 so `101` fell through, and
  `es`/`fr`/`it`/`pt` lacked the `many` CLDR 38 added for whole millions.
* The oracle has one defect of its own, documented in the test: `intl`
  computes the operand `i` as `n.round()` where CLDR says integer digits, so
  it reads 1.5 as `i = 2`. Values ending in `.5` are asserted by hand against
  CLDR's published samples instead.
* **37 languages became 74.** Slovenian was a hard stop when the marketplace
  app wanted a fifth language, and the missing list included Bulgarian,
  Catalan, Latvian, Lithuanian, Persian, Bengali, Urdu, Filipino and thirty
  more. Hand transcription would normally be the wrong trade for a library
  whose point is not shipping wrong plurals; with the oracle it is not, and
  the oracle rejected three of my transcriptions (`is`, `kn`, `mr`) by name
  and sample. Ordinals stay at 36: `intl` ships no ordinal table, so there is
  nothing to check them against.
* **`file_per_locale` with `fill_missing_from_base` did not compile.** A
  filled message renders as the base locale does, formatters included, so a
  French part file declared `_enDateYMMMd` that the English part already had,
  in one library. Formatters are now assigned to the locale they format *for*
  rather than the locale that uses them.
* **A select branch called `values` or `index` generated an enum that did not
  compile**, silently: the escaping mechanism knew about `hashCode` and
  `toString` but not the two members every enum declares itself. An enum
  specific reserved set, so an ordinary message called `index` is untouched.
  The `json` and `yaml` fixtures carry such a select now, so `dart analyze`
  is the proof.
* **A configuration error exited zero.** `L10nPlusConfig.parse` reports a bad
  value and carries on with the default, and the CLI decided the exit code
  from the generator's diagnostics alone, so CI passed on a project generating
  from a configuration it had already called wrong. `run()` now takes the
  configuration's collector, which is what the `build_runner` adapter always
  did. `test/cli_exit_code_test.dart` runs the CLI as a process, because the
  exit code lives in `bin/` and nothing in process reached it.
* `plural_type_mismatch` printed "is a null here" when the other side was a
  plain number.
* Diagnostics at scale: a collapsed subtree now says how many messages it
  covers, and the base locale's *file* is named, not only a line number —
  "line 4" names nothing once `file_pattern` spreads a locale over nine files.
* The generated library now exports `L10nLocale`, which its own `of` signature
  names. The README's usage snippet did not compile without a second import
  nobody chose, and its Flutter section showed one import where an app needs
  two plus `flutter_localizations`.

## Milestone 20 — ordinals for every language that has plurals (done)

The previous milestone left 38 languages able to count things but not to
number them, and said the blocker was the oracle: `package:intl` ships no
ordinal table, so there was nothing to check hand written rules against.

* **The oracle is ICU, reached through Node.** `Intl.PluralRules(locale,
  {type: 'ordinal'})` is the CLDR ordinal table as ICU implements it.
  `tool/derive_ordinal_oracle.mjs` dumps its answer for 1214 values per
  language — every integer to 1200, whole thousands, and fractions — into
  `test/data/cldr_ordinals.json`. The answers are **vendored**, not queried,
  so the test suite still needs nothing but Dart; the script is in the
  repository so the file can be regenerated and disagreed with, and its
  header records which ICU and CLDR produced it.
* The dump refuses to write a language ICU has no data for: an unknown tag
  resolves to the runtime default, and vendoring `en-US` under another name
  is exactly the failure this is meant to prevent.
* **36 ordinal languages became 74**, the same set the cardinal table covers,
  and a test asserts the two agree — a language that can count but not number
  is a gap rather than a decision.
* The oracle found three defects in the 36 that were already there:
  `vi` and `ms` were listed as having no ordinal categories when CLDR gives
  both a `one`, and `en` was written over the operand `i` where CLDR writes
  `n`, so `1.5` selected `one` and rendered "1.5st".
* That last one exposed something worth writing down: **some CLDR ordinal
  rules read `n` and some read `i`**, and the choice is per language, not
  stylistic. English `1.5` is `other`; Azerbaijani `1.5` is `one`. Both are
  nonsense input, but they are ICU's nonsense, and the table now matches it
  language by language rather than picking one operand and hoping.
* Nepali's `n = 1..4` needed the same integer guard Arabic's ranges needed in
  the previous milestone. A CLDR range never matches a fraction; written as
  `>= 1 && <= 4` it does.
* Verified the guard by regression, the way the formatter goldens are: putting
  the English rule back on `i` makes the differential test fail with
  `en(1.5): ours=one icu=other` and nothing else.
* `evaluation/marketplace` gets its `selectordinal` back — the message had to
  be removed when Slovenian could not generate one.

## Milestone 21 — next slice

Ordered by what the evaluation showed actually costs time.

1. **A rename should read as a rename.** Renaming one key in the base locale
   produces one `missing_key` and one `extra_key` per locale, each correct and
   neither aware of the other. Pair a missing key with an extra key that has
   the same argument set and the same shape, and say so. Turns 2N errors into
   N hints with the fix in them.
2. **`unused` needs the key path, not the member name.** On the 810 message
   app it reported nothing while the app used about eight keys, because with a
   conventional `feature.group.title` scheme every leaf name appears
   somewhere. The scan errs toward "used" on purpose, but at scale with that
   naming it never fires at all. Matching `.group.title` rather than `.title`
   would keep the conservatism and recover most of the value; a chain of
   two segments is still a text scan, not an `analyzer` dependency.
3. **A translation status summary.** `analyze` prints "0 error(s), 18
   warning(s)" for 269 untranslated messages. Per locale counts —
   translated, untranslated, total — would answer "how far along is French",
   which is the question a partial rollout is actually asking.
4. **`ignored_placeholder_type` should not fire on what `gen_l10n` writes.**
   `"type": "String"` on a select placeholder is the canonical ARB spelling;
   warning about it puts noise on every select of every imported bundle, and
   the user cannot remove it without editing a generated file.
5. **Name the function the reader has.** Forgetting
   `initialize<Class>Formatting()` fails with `intl`'s own message, which says
   to call `initializeDateFormatting`. The lazy finals are initialized once,
   so wrapping the initializer to rethrow with the generated function's name
   costs nothing at steady state.
6. **Did you mean.** `unknown_config_key` lists eleven keys where a one edit
   distance match would name the one.

## Milestone 22 — earlier open items

1. **`context.l10n` and locale switch cost.** Needs a Flutter harness, and the
   numbers would mostly be Flutter's rather than this library's.
2. **YAML metadata.** Only if a convention appears that people actually use.
3. **Ecosystem.** TMS import/export, PO/XLIFF, OTA, IDE plugin — a different
   scale of work from everything above.


Nothing measures the central claim — a `const` graph with no lookup and no
allocation — beyond one example test asserting identity. Worth numbers before
the ecosystem work starts.

## Milestone 23 — ecosystem

7. **TMS import/export** (Crowdin, Lokalise, POEditor).
8. **PO / XLIFF** interchange formats.
9. **OTA translations.** This is the first feature that genuinely needs a
    runtime map path alongside the generated one, and the first that makes
    `setLocale` asynchronous.
10. **IDE plugin / hot reload daemon.**

## Benchmarks

`example/benchmark/l10n_benchmark.dart`, run with
`dart run benchmark/l10n_benchmark.dart`. Numbers and method are in
`architecture.md`. Still unmeasured: `context.l10n` lookup and locale switch
rebuild cost, both of which are Flutter's costs more than this library's.
