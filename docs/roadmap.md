# Roadmap

## Milestone 0 — vertical slice (done)

Everything below works end to end today.

* JSON source format, nested namespaces
* span-aware JSON parser
* ICU parser: literals, `{placeholder}`, `plural` (`=N` and categories), `select`,
  `#`, arbitrary nesting, apostrophe quoting
* argument inference: `String`, `num`, generated select enums
* CLDR plural rules for 30 languages, inlined per locale at generation time
  (the whole of CLDR since Milestone 19)
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

## Milestone 21 — bugs and coverage before publishing (done)


Eight things found by using the library rather than by testing it.

* **Type name collisions.** `auth.login` beside `auth_login` generated
  `$AuthLogin` twice, with no diagnostic; `dart analyze` reported
  `duplicate_definition` in generated code. Every top level name — interfaces,
  their per locale implementations, select enums, the class and the locale
  enum — is now claimed in one registry, and a second claim is
  `type_name_collision` naming both keys.
* **The app did not start in the system locale.** `create<Class>Controller()`
  is documented as following the operating system and defaulted
  `systemLocales` to `const []`, which resolves to the fallback. Flutter never
  reports `didChangeLocales` at start up, so a Russian phone opened the app in
  English. The factory now reads the platform's locales through
  `WidgetsFlutterBinding.ensureInitialized()`, which is also the one a widget
  test can substitute.
* **The whole CLDR plural table.** The curated forty language table blocked
  `bg`, `sl`, `lv`, `fa`, `ta`, `mr` and a hundred others outright.
  `tool/update_cldr_plural_rules.dart` compiles CLDR 48 into the same
  condition format: 222 cardinal and 107 ordinal languages, checked against
  CLDR's own samples *and* against `package:intl` — which are complementary,
  because each catches what the other misses. The hand written Arabic rule was
  missing the integer guard a CLDR range implies.
* **`ignore_diagnostics`.** Warning codes a project has decided about. Only
  warnings, an unknown or always-error code is reported, and the suppressed
  count is always printed.
* **`=1` covers `one`.** A `gen_l10n` bundle writing `=0 =1 other` was told
  English `one` was missing. It is not: English defines `one` as one exact
  value, and `=1` renders all of it. Ranges are not attempted, and `offset:`
  disables the check.
* **The format names `gen_l10n` writes.** `decimalPattern`, `percentPattern`
  and `scientificPattern` accepted as spellings of the styles that existed,
  folded at the entry points so both spellings share one formatter.
  `compactCurrency` and `compactSimpleCurrency` added as real styles, and
  `decimalPercentPattern` as its own — it is the constructor that takes
  `decimalDigits`, so aliasing it to `percent` would have dropped them.
* **`extra_keys: warn`.** For teams on a TMS, where a translation outlives the
  key it was written for. The key is ignored, and the output is what deleting
  it by hand would give.
* **Four smaller ones.** A YAML message starting with `{` now gets a
  diagnostic saying to quote it; the builder declares `.yaml` and `.yml` as
  required inputs; a `DateFormat` built before its symbols are loaded throws
  an error naming the generated initializer; and the region fallback order —
  `en_NZ` to `en_AU` because `AU` sorts first — is documented and pinned by a
  test that says out loud that it is arbitrary.

## Milestone 22 — the second week (done)

Five of the six items the evaluation named as what costs time after the first
day. The sixth, naming the generated initializer in the date symbols error,
had already landed.

* **`unused` stopped lying.** It matched the leaf member name, so a project
  whose messages are `title`, `subtitle` and `action` under forty namespaces
  used each of those six words on its first screen, after which every key in
  the project counted as used, forever. On the 810 message evaluation app it
  reported "No unused keys. 270 checked" while the app touched eight of them.
  A message is now used only when **every** name on its path appears:
  reaching `t.wallet.limits.title` means writing `.wallet`, `.limits` and
  `.title` somewhere, in one expression or spread across locals and helpers,
  so the rule costs nothing in safety. The same app now reports 234 of 270.
* Those findings collapse by unreachable namespace, the way `missing_key`
  already did, and the report separates findings from messages: "234 of 270
  key(s) appear unused, in 19 place(s)". `UnusedKeyReport` carries both,
  because CI counts one and a person reads the other.
* **`--watch`.** Regenerates on a change to a translation, `l10n_plus.yaml`
  or `pubspec.yaml`, re-reading the configuration each time so editing it
  needs no restart, and surviving errors so a broken file can be fixed in
  place. Nothing else in the project is watched: saving a Dart file must cost
  nothing. Debounced by 120 ms, because an editor saves in bursts and a
  save-and-format is two of them. Refused for `analyze` and `unused`, which
  answer a question once.
  * The integration test caught a real defect on its first run: paths were
    compared after `p.canonicalize`, which does not resolve symbolic links,
    so a project reached through one — every temporary directory on macOS —
    matched nothing and never rebuilt. Comparison is now against the paths
    handed to `watch`. A watcher that silently stops watching is worse than
    no watcher, which is why the test drives a real process and edits a real
    file twice.
* **`analyze` says how far each locale has got.** "0 error(s), 18 warning(s)"
  for 269 untranslated messages was not an answer to the only question a
  partial rollout asks. `LocaleCoverage` counts messages rather than the
  subtrees the warnings collapse to, and the table is printed only when
  something is incomplete — a column of 100%s on every run is noise.
* **`ignored_placeholder_type` stopped firing on what `gen_l10n` writes.**
  `"type": "String"` on a select placeholder is required by gen_l10n's own
  schema and `Object` is its default, so warning about either put a line on
  every select of every imported bundle, about something nobody can change
  without hand editing a generated file. A declared `int` still warns: that
  is an author who thinks the argument is a number.
* **`unknown_config_key` names the near miss.** `file_per_local` gets "Did you
  mean file_per_locale?" ahead of the list of every key. Only a genuine near
  miss qualifies — a third of the length, at most three edits — because a
  wrong guess is worse than the list.

## Milestone 23 — a rename reads as a rename (done)

* Renaming a key in the base locale made it missing everywhere and left the
  old name extra everywhere: one edit, two diagnostics per locale, neither
  aware of the other. On the four locale evaluation app that was six errors
  for one rename, to be paired up by eye.
* When a namespace has **exactly one** missing key and **exactly one** extra
  one, and both are the same kind of node, `renamed_key` replaces the pair and
  names both sides with their files and lines.
* Deliberately narrow. Two missing and two extra could be two renames or four
  unrelated edits, and guessing wrong would send someone renaming the wrong
  key; those still get the plain diagnostics. The finding says so itself:
  "if they are unrelated, add one and remove the other and each will be
  reported on its own."
* Severity follows the pair it replaces, so a project running both
  `fill_missing_from_base` and `extra_keys: warn` gets a warning and everyone
  else gets an error. One error where there were two is still one build
  failure.
* A renamed *group* is one finding too, and says how many messages move with
  it.


## Milestone 24 — the central claim, measured (done)

The roadmap has said since Milestone 19 that nothing measured the claim the
whole design rests on — a `const` graph with no lookup and no allocation —
beyond one example test asserting `identical` on two accessors.

* **`const_graph_test.dart`** reads the emitted source instead of sampling the
  result: every namespace accessor must return a `const` instance, every
  implementation class must have a `const` constructor, and the locale enum
  must hand out constants too. `identical` proves one instance is canonical
  and cannot say anything about the next accessor somebody adds.
* Verified by regression, the way the formatter goldens are: deleting the
  `const` the emitter writes makes it fail naming all twelve accessors that
  would start allocating on every read.
* **`example/test/flutter_cost_test.dart`** answers the other half.
  `AppLocalizations.forLocale` and three getters cost 6 ns; the same through
  `context.l10n` costs 44 ns; `AppLocalizations.of(L10nLocale.parse(tag))`
  costs 394 ns. So the scope read is about eight times the direct call, and
  that difference is `dependOnInheritedWidgetOfExactType` — which confirms
  what this entry used to predict: the number is Flutter's, not ours.
* Switching locale over 200 widgets, 100 of them readers: 7.4 ms median,
  14.2 ms on the first switch because it compiles the second locale's path.
  Under `flutter test`, so an upper bound and mostly Flutter's rebuild.
* What is asserted rather than printed is the shape: exactly the hundred
  readers rebuild and the other hundred never do, on every switch. A scope
  that rebuilt its whole subtree would pass any timing threshold on a fast
  machine and would be the actual defect.
* No timing is asserted anywhere, for the reason already in the file: a
  threshold that fails on a slow CI box teaches people to ignore the suite.

## Milestone 25 — the plural count is formatted, and the operands follow it

Milestone 25 asked three questions. Two are answered in code, the third is
unchanged.

* **Measured first.** `intl` solves the `1.0` problem with `precision`, and
  running `intl-0.20.3` shows the default truncates a whole double, so
  `Intl.plural(1.0)` is `one`; `gen_l10n` never passes `precision` at all.
  Every Dart tool selects `one` for `1.0`.
* **`precision` was the wrong shape.** `v` belongs to the *formatter*, not the
  value: `NumberFormat.currency(locale: 'en')` renders `1` as `USD1.00` (CLDR:
  `other`), `decimalPattern` renders it `1` (CLDR: `one`). So the roadmap's own
  question — separate value from rendering without a second parameter in every
  signature — has an answer wherever the format is declared in the message,
  because the generator already knows it.
* **A format on a plural count is honoured now.** It was silently discarded,
  which is why nothing rendered wrongly here while `gen_l10n`, run on the same
  bundle, emits `USD1.00 card`. The count renders through the declared format,
  in `plural` and `selectordinal`, before and after an `offset:`, with currency
  options and per locale.
* **`PluralOperands.formatted`** reads the operands off the digits the
  formatter produces: round to its maximum, trim trailing zeros to its minimum.
  The bounds are read off the `NumberFormat` at run time, because a currency
  decides its own fraction digits and the generator cannot know them. The
  runtime keeps its zero dependencies — it receives two `int`s.
* **Only where the count is really displayed through it.** A plural of pure
  words shows no number, and a branch interpolating `$count` raw shows
  `toString()`, so both keep reading the value. The emitter walks the branches
  rather than assuming.
* **`format_plural_numbers` came along, on the same principle** — it is the one
  behaviour change beyond declared formats. Its decimal pattern rounds at three
  digits, so `1.23456` now has `v == 3` and `f == 235`, matching the `1.235`
  it prints. Leaving it out would have kept the very mismatch being fixed.
* **The default did not move.** A count with no formatter still reads its
  value, so `1.0` is still `one` in English, still matching the ecosystem.
* **`dropped_placeholder_format`** (warning) stays for select arguments, which
  have no number to format. Probe 17 replays it; probe 18 shows the plural
  case being honoured.
* **Verified by execution.** The formats golden gained three formatted plurals
  and `goldens_runtime_test.dart` runs them: `USD1.00 cards` against
  `USD1 card` for the same `1`, Russian never reaching `один` under a currency,
  and `1.23456` printing `1.235 cards`. Reading the source proves the call is
  there; running it proves the branch.
* **Probe 16 had rotted.** It demonstrated `unknown_plural_language` with `cy`,
  which the 222 language CLDR import has since added, so it silently stopped
  demonstrating anything. It uses `tlh` now, and `transcript.txt` — which had
  drifted from the generator in four other places — is regenerated.
* **YAML metadata — answered: no, and now for a reason.** `slang` reads YAML
  and is type safe, so it had every reason to invent the convention. It did
  not: it writes types into the message (`{amount: currency}`) — which this
  library already parses out of YAML, JSON and ARB alike — and of `@key` prose
  in YAML its documentation says "Currently, not parsed and no comments will
  be generated". Nothing to copy; YAML stays metadata free.

### What is still open

1. **Ecosystem.** TMS import/export, PO/XLIFF, OTA, IDE plugin — a different
   scale of work from everything above.

## Milestone 26 — ecosystem


7. **TMS import/export** (Crowdin, Lokalise, POEditor).
8. **PO / XLIFF** interchange formats.
9. **OTA translations.** This is the first feature that genuinely needs a
    runtime map path alongside the generated one, and the first that makes
    `setLocale` asynchronous.
10. **IDE plugin / hot reload daemon.**

## Milestone 27 — translations without a `BuildContext` (deferred)

Today a translation is reached three ways: `AppLocalizations.forLocale` and
`AppLocalizations.of` for a locale you name yourself, and `context.l10n` for
the one the user is reading in. Code with no `BuildContext` and no locale of
its own — a repository, a use case, a notification builder — has to be handed
the controller, and the request that keeps coming is the fourth way: an ambient
`AppLocalizations.current` that is simply the active locale's translations.

Deferred rather than rejected. The design below is settled; what is not settled
is whether the footgun in it can be made loud enough to be worth shipping.

### Why it is not in yet

`context.l10n` creates an `InheritedNotifier` dependency, which is what makes
`setLocale` repaint the screen. `AppLocalizations.current` creates none. A
widget that reads it renders correctly the first time and then keeps the old
language after a switch — silently, on one screen out of forty, for the users
who change language. That is exactly the class of failure this library exists
to move to build time, so adding an API that reintroduces it needs more than a
paragraph in the README.

Two smaller objections, both answerable: global mutable state leaks between
tests (`resetCurrent()`, and nothing installed by default), and a server
isolate serving several languages at once has no single "current" locale
(the feature is opt-in, and pure Dart has to install it by hand).

### The design, if it is built

* **A cell, not a static.** `L10nCurrent<T extends BaseTranslations>` in
  `packages/l10n_plus/lib/src/current.dart`: holds `T?`, `value` throws a
  `StateError` naming the call to make when nothing is installed, `install`
  asserts in debug when a live owner is being replaced, `reset` clears. A
  generic object stays type safe where a generic static cannot.
* **The controller writes it, so there is one source of truth.**
  `L10nController` takes an optional `L10nCurrent<T>`, writes on construction
  and in `_set`, clears in `dispose`. `current` and `context.l10n` then cannot
  disagree, because the second is not a second copy of the first.
* **`global_translations: false`**, top level rather than under `flutter:`,
  because a pure Dart project may want it too. With it off the output is byte
  for byte what it is today. `global_getter: t` would additionally emit a top
  level getter, the shape `slang` has; probably not worth it, since `t` is the
  name most easily shadowed by a local.
* **Generated surface**, beside `forLocale`/`of`/`resolve`: `current`,
  `setCurrentLocale` (chiefly for pure Dart and tests) and `resetCurrent`. The
  Flutter factory passes the cell into the controller, so an app that builds a
  controller has the ambient getter working without a second setup step, and an
  app that never asked for the option never sees any of it.
* **Loudness, in order of how much it buys.** A debug assert on double install
  — two controllers over one cell is a hot restart or a test suite, and the
  symptom is "current shows the wrong language" with no other trace. Then the
  dartdoc on `current` itself, which is where the warning is actually read.
  Then, maybe, a debug assert when `current` is read during a build; that
  depends on `WidgetsBinding.debugBuildingDirtyElements` covering every rebuild
  path without false positives, which nobody has checked. It is a separate
  step, after the rest works, not part of a first version.

### What would have to be verified

That the goldens for every fixture are unchanged with the option off; that
`setLocale` moves `current` and `dispose` clears it; that `context.l10n` and
`current` agree after a switch, asserted in a widget test rather than argued
from the code; and that the double install assert fires. Plus the README
section saying plainly which of the two readers rebuilds — the one thing a
reader has to know before choosing between them.

## Benchmarks

`example/benchmark/l10n_benchmark.dart`, run with
`dart run benchmark/l10n_benchmark.dart`. Numbers and method are in
`architecture.md`. Still unmeasured: `context.l10n` lookup and locale switch
rebuild cost, both of which are Flutter's costs more than this library's.
