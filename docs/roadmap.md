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

## Milestone 28 — four gaps closed at once (done)

Numbered 28 because 26 and 27 below are the open and the deferred section, kept
at the end where a reader looks for what is left.

Four of the ten items the competitive review listed as "where we are behind",
done in parallel because they touch disjoint files, and each verified by
execution rather than by the shape of the source.

* **Rich text.** `terms(rich)` yields `List<L10nSpan>` in the pure Dart file and
  a `TextSpan` wrapper in the Flutter glue that requires one builder per tag the
  message contains, so a forgotten tag is a compile error — a guarantee `slang`,
  which has the feature, does not make. Tags are a layer over the ICU AST rather
  than a sixth node kind, so the model keeps the plain parse and signature
  inference, cross-locale validation and the doc comments needed no new case; a
  currency format inside a tag works with no second implementation. A rich
  plural is refused (`rich_unsupported_choice`): one builder per tag only
  type-checks while the tag set is static. The span types are re-exported only
  in a project that has a rich message, so every existing golden is byte for byte
  what it was.
* **`export` / `import`.** CSV for a spreadsheet, ARB for a TMS, and back again
  by splicing each string at its own leaf's value span, so key order, blank
  lines, YAML comments, indentation and line endings survive and the diff is the
  translations alone. Dry run by default. Both commands run *before* cross-locale
  validation, because under the default configuration the incomplete locale is an
  error and that locale is the one being exported for. The round trip is asserted
  byte-identical over JSON, YAML, ARB and a split layout, in both formats, with a
  count assertion so that "nothing changed" cannot pass vacuously.
* **Right to left.** `L10nLocale.isRightToLeft` from CLDR 46's own two files,
  decided by script and never by region; `TextDirection` on the Flutter locale
  and the controller; and `fill_direction_mismatch` for the case that made the
  gap worth closing — `fill_missing_from_base` substituting left-to-right base
  text into a right-to-left locale, which ships because the screen *looks*
  finished. Counted in messages rather than findings, since `missing_key`
  collapses a whole untranslated namespace into one diagnostic and would
  understate it by two orders of magnitude.
* **Region fallback.** The generic locale now wins by guarantee rather than by
  accident of the lineage walk, and a region sibling is chosen by script
  agreement and then by tag, so renaming a translation file can no longer change
  what the app renders. Still no CLDR affinity table, and still said out loud.

Diagnostics went from 72 codes to **81**: `rich_tag_mismatch`,
`rich_invalid_markup`, `rich_unsupported_choice`, `fill_direction_mismatch`,
`invalid_interchange`, `unknown_interchange_key`, `unknown_interchange_locale`,
`unknown_interchange_column`, `unplaceable_key`.

### What the review found that this does not fix

* ~~**Interpolated values are not bidi-isolated.**~~ **Done in Milestone 31.**
  The prediction that it would mean invisible characters in every golden was
  wrong in one respect: the option is off by default, so no existing golden
  carries them.
* **No PO/XLIFF and no vendor API.** ARB and CSV travel; Crowdin and Lokalise
  still mean a person in between.
* **The runtime tier is untouched**: no over-the-air overrides, ~~no lazy
  per-locale loading~~ (**done in Milestone 34**), ~~no linked translations~~
  (**done in Milestone 33**), ~~no dynamic key access~~ (**done in Milestone
  35** — all four of them, in the end). Those four all rewrite the emitter and the model, which is
  why they were not attempted alongside rich text, and the first of them is the
  item below worth more than everything in this milestone.

## Milestone 37 — an element that is a record (done)

The gap Milestone 36 left open and wrote down: a list whose elements are
objects, which is the onboarding shape where every step has a title and a body.

* **One interface and one class per locale**, not one per element. The values
  are known while generating, so the class carries them as `final` fields and
  the list is one `const` that Dart canonicalizes — reading it allocates
  nothing, as everything else here does. Named constructor arguments, because
  a record of five fields built from five positional strings is a line nobody
  can check by eye.
* **The first element declares the fields, and the rest have to agree.** A list
  has one element type; an element missing a field, or carrying one the first
  element has not, is an error naming both and listing the fields. That is the
  check this feature is for, and the one a package that builds a map at run
  time cannot make: there a missing field fails at the screen that read it.
* **The same trick as Milestone 36, one level deeper.** An object element
  becomes a group of leaves in the tree, so the fields are messages — links
  resolve inside one — and the cross locale check compares `pages.0.body` like
  any other key. No new diagnostic code: `invalid_collection_entry` covers
  every way a record can be wrong, and `identifier_collision` covers two
  fields becoming one Dart name. The registry stays at **103**.
* **Overrides reach one field.** With them on each field becomes a private
  member consulting the store, and the element is built from those, so a
  bundle names `onboarding.pages.1.body`. Executed rather than argued.
* **A cascade I had to unlearn.** The first version reported both "this field
  takes an argument" and "this element has no such field", because the second
  check ran over fields the first had just rejected — and on the declaring
  element it said *"Element 0 has no title, which Element 0 has"*. One error
  per mistake is now asserted for all three field refusals.

### What this one leaves open

* **A list of lists is still refused**, and the reason has not changed: the
  index would have to be a type. Nothing asks for it.
* **A record is one level deep.** A field that is an object would need a type
  of its own and then so would its fields; there is no reason it could not be
  done, only that nothing has needed it and each level is another generated
  type to name and claim.
* **The field order is the first element's.** Later elements may write their
  fields in any order — the model reads them by key — but the generated
  constructor takes them in the first element's order, so moving a field in the
  first element changes the generated signature while changing no behaviour.
  It is a `const` constructor with named arguments, so nothing breaks; the
  golden diff is just larger than the edit looks.
* **Nothing checks a record against anything outside the project.** The fields
  are a contract with the screen that reads them, and the compiler holds that
  one. A record that is meant to match an API's shape is matched by nobody.

## Milestone 36 — a value that is a collection, not a message (done)

The last row of the capability matrix `slang` held alone. An array becomes a
`List<String>`, a key with the `(map)` suffix becomes a `Map<String, String>`,
and both are `const`.

* **A flag on the group, not a third node kind.** The translation tree is
  `sealed` with two kinds, and `LinkNode` had already shown what adding one
  costs. There was no reason to here: a list is a group whose children are
  keyed by index, and only the accessor differs. So `CollectionKind` is a field
  and the elements are ordinary leaves.
* **Which paid for itself immediately.** The elements are parsed as messages,
  so placeholders, formats and links work inside one. Signature inference
  reads them, which is how an element that takes an argument can be refused.
  And the cross locale check compares the element keys, so **a list that is
  three long in English and two in Russian is `missing_key` for `steps.2`**, at
  the right line, in words the project already had. The rename detection even
  catches a locale that wrote `countries` where the base wrote
  `countries(map)`.
* **One new code**, `invalid_collection_entry`, registry at **103**, for the
  three things an element cannot be: a message that takes arguments, a rich
  message, and a collection of its own.
* **No arguments, and the reason is the accessor.** A list whose elements took
  values could not be `const`, and its signature would be the union of what
  each element happens to use — a parameter list no caller can read. The same
  shape of refusal `dynamic_keys` makes, for the same reason.
* **`runtime_overrides` decides the shape, for the third time.** Off, the
  elements are written into a `const` collection and reading one allocates
  nothing. On, each becomes a private member that consults the store, so a
  bundle can replace one item of a list. Executed, not argued. The override key
  is where the `(map)` suffix is stripped — it is a directive to the generator,
  not part of the message's identity — so a bundle names `countries.fr`, and
  `check-overrides` refuses `steps.9` with the nearest key offered.
* **Two things had to be taught.** Coverage counts the elements, because a list
  of three bullet points is three messages a translator is being asked for; and
  the `unused` scan looks for the collection's name rather than its elements',
  because one unused list is one finding and one edit.
* **Both source formats, and honestly not the third.** JSON arrays and YAML
  sequences; ARB has no arrays, so an ARB bundle cannot express either, which
  is the format's limit rather than a gap here.

### What this one leaves open

* ~~**A list of objects is refused.**~~ **Closed in Milestone 37**, and it
  needed one interface rather than a type per element — the prediction here
  that it would need "a generated type per element" was wrong in the way that
  made it look bigger than it was.
* **A map's `[]` is still `String?`.** That is Dart's, not ours, and it is why
  the README points a *lookup* at `dynamic_keys` instead: a key enum's lookup
  is total and a typo is a compile error. A map is for the times you need the
  whole thing. Two features that look like one and are not, and nothing in the
  build tells a project it has reached for the wrong one.
* **Nothing checks that a list is used in order.** `steps[1]` in Dart compiles
  whatever the list holds, and a locale that reordered its elements renders
  them reordered. The index is the key, so the cross locale check sees matching
  keys and says nothing. A list is the one shape where order is content and
  nothing here verifies it.
* **An empty list is allowed.** `const []` is valid Dart and a translator
  emptying a list is a legitimate edit, so there is no diagnostic — but a
  screen that assumed three items gets none, and only the cross locale check
  would notice if another locale still had them.

## Milestone 35 — a string from outside, turned into a key (done)

The last of `slang`'s four runtime-tier advantages, and the one this document
had called "the thesis's opposite" twice. It was right about the usual shape of
the feature and wrong that there is only one shape.

* **The question was where the string is, not how much checking to give up.**
  Something has to turn a value from outside into something the program knows,
  that step is the only one that can fail, and so it is the only one allowed
  to: `ErrorsKey.tryParse` returns `ErrorsKey?`, and `t.errors[key]` is total
  over the enum with a non-nullable `String` out. The same shape the library
  already used for select branches, where its own test says *a typo cannot
  reach run time*.
* **The enum carries the translation key, not the Dart name.** `rate_limited`
  is what a server sends; `rateLimited` is what this generator made of it, and
  making the contract the identifier would make it a function of naming rules
  no server should have to know. Relative to the namespace, too, because the
  namespace is the contract.
* **The lookup delegates to the members** rather than repeating their text, so
  an overridden message is overridden through it, a linked one resolves the
  same way, and it cannot drift from what it stands for. The runtime test
  installs a bundle and reads the same message both ways.
* **Two kinds of message are refused**, with the reason and the fix:
  `unaddressable_dynamic_key` for one that takes arguments — a string cannot
  carry its values, and a map of them is the run time lookup this avoids — and
  for a rich message, which renders spans rather than a string. One new code,
  registry at **102**. Everything else reuses `invalid_config` and
  `identifier_collision`.
* **And the measurement found something I did not expect.** Declaring a
  namespace addressable costs **nothing**: 49,047 bytes either way, because
  until something calls `[]` `dart2js` drops the lookup and every reference it
  held. Calling it costs that namespace — 58,298, so 9,251 bytes for 44
  messages in four locales. Declaring nine and calling one costs exactly one,
  which is the per-namespace design measured rather than argued. And calling
  all nine costs **141,787 against 49,047**, which is what addressing a whole
  project by string costs and is the shape of a flat key-to-message map.
* **Which closes the loop with Milestone 34.** `slang` generates that flat map
  by default — `flat_map`, default `true`, and its over-the-air overrides
  require it — so its translations cannot be tree-shaken, which is why lazy
  loading matters as much to it as the previous milestone measured it not
  mattering to us. The two features are one fact from opposite ends: what the
  compiler is allowed to drop. Neither of us is wrong; we have made different
  things droppable.

### What this one leaves open

* **No arguments, by design, and that is a real limit.** An error code whose
  message needs a value cannot be addressed by key at all, so a project splits
  its namespace. A `fill`-shaped call taking a map would serve it and would be
  exactly the unverifiable thing the feature was shaped to avoid; the honest
  position is that this feature does not cover that case rather than that it
  covers it badly.
* **The whole project cannot be addressed**, deliberately, and the 141,787 in
  the table is the argument. A project that wants it writes nine entries and
  pays for nine.
* **`values` is a contract nothing checks against the server.** The list is
  generated and an application can compare it to whatever the API documents,
  but nothing in this repository reads an OpenAPI document or a protobuf and
  tells you the two have diverged. That is the check that would make the
  feature complete, and it is a different tool.
* **A key enum is not a locale-aware list.** `ErrorsKey.values` is the same in
  every locale, which is right — the keys are the API — but it means a locale
  that is missing a key renders the base locale's text through the lookup
  exactly as it does by name, and the lookup is not where you would learn
  that. `analyze` is.

## Milestone 34 — locales that arrive when they are needed (done)

`deferred_locales: true`, the last of `slang`'s four runtime-tier advantages.
The feature itself is small; what it cost was a decision about the API and
what it taught was a measurement that argues against it half the time.

* **The layout is the feature.** `file_per_locale` writes `part` files, and a
  `part` is compiled into its library — there is nothing for a deferred import
  to load. So the locales become libraries, imported `deferred` by the shared
  file, and the option requires `file_per_locale` rather than implying it: the
  layout key decides which files a repository holds.
* **The fallback locale is never deferred**, so something is always
  renderable, and an unloaded locale renders *its* text. That is the decision:
  `forLocale` stays synchronous and non nullable, and an unloaded locale is an
  unsupported locale — a failure mode the library already had, reached by a
  different route, rather than a new one in the middle of the API it exists to
  make safe.
* **`const` survived again.** `const` of a class behind a deferred prefix is a
  compile error, so each locale library exposes one public getter building its
  own `const` instance, and what crosses the boundary is an interface the
  shared file declared. `identical` holds across two reads, asserted, because
  it is the property that could have been lost.
* **The controller makes the feature invisible.** `setLocale` stays
  synchronous: it switches, starts the load and repaints when the chunk lands.
  `setLocaleAsync` is for a caller that would rather not show the frame that
  reads as the fallback. Driven through a real widget tree, including a
  controller disposed mid-download, which is what a popped settings screen is.
* **And the measurement says not to turn it on by default.**
  `evaluation/bundle_size.py` is in the repository because the figure should be
  re-runnable. 396 messages in four locales, `dart compile js -O4`: the first
  download goes from 189,632 bytes to **113,148** when the entry point reads
  every message — and from 49,047 to **69,995**, forty-three percent *worse*,
  when it reads one. Two causes, both measured: `dart2js` already tree-shakes
  messages nothing reads, because a generated message is a getter on a `const`
  class and an unused getter is dead code — which is exactly what is not true
  of a package that builds a map at run time — and the deferred loader is a
  fixed 20,948 bytes, since the chunks in that row hold 597 bytes each. At 36
  messages per locale the trade has already inverted.
* **No new diagnostic code at all**, which is unusual for a milestone this
  size and is a consequence of the fallback decision: the one thing a project
  can get wrong is asking for `deferred_locales` without `file_per_locale`, and
  that is the existing `invalid_config` with the line to add in its details.
  There is no wrong *state* to report, because an unloaded locale is not a
  wrong state. The registry stays at **101**.

### What this one leaves open

* **No assert on reading an unloaded locale.** This project's usual answer to a
  quiet hazard, and it cannot be used here: the legitimate path reads the
  fallback for a frame or two while the chunk arrives, so the assert would fire
  on the feature working. An application that bypasses the controller and never
  calls `load()` gets the fallback with nothing saying so.
* **Nothing splits one locale.** A chunk is a whole language. An application
  that shows three screens of nine namespaces downloads all nine, and
  per-namespace chunks would need a deferred import per namespace per locale —
  which is where `dart2js`'s own tree-shaking is already better than anything
  this generator could decide.
* **The formatters are duplicated per chunk.** Independence costs that, and it
  is inside the measurement above rather than beside it.
* **Measured with `dart compile js`, not with `flutter build web`.** The
  compiler and the optimisation level are the ones a release Flutter web build
  uses, so the figures are about the translations; what they are not is a
  fraction of a real Flutter bundle, which is a megabyte and a half of engine
  before any of this.
* **A deferred load does not complete under a widget test's fake clock, and
  starting one there spends the locale.** Measured while writing the test: a
  `load()` begun in fake async never finishes, and awaiting its future inside
  `runAsync` afterwards does not rescue it, because `loadLibrary` hands out one
  future per library and that one belongs to a zone the test has stopped
  advancing. So an application testing a locale switch has to drive it inside
  `runAsync`, and no two tests in one isolate can use the same locale. Nothing
  in the library says so except the test, the README and this line; a
  `WidgetTester` extension could, and would be the Flutter package growing a
  test-only surface it has so far done without.
* **Nothing is measured on the VM or on AOT**, where a deferred import loads
  nothing and the feature is inert. That is the honest shape — there are no
  chunks off the web — but it means the option is dead weight in a mobile-only
  project, and nothing in the generator says so.

## Milestone 33 — one message inside another (done)

`@:other.key`, the second of `slang`'s four runtime-tier advantages to be
taken. (The sentence here used to add "and the last of them this library's
thesis has any business taking", on the grounds that lazy loading is a question
about build output rather than a feature. Milestone 34 took it anyway, and
found that the build output question was the interesting part.) It brings with it the one capability
ICU cannot express: two plurals in one sentence, each selecting on its own
count.

* **Resolved while generating, in two forms.** A link to a parameterless
  literal target is written in place — transitively — and the result is byte
  for byte the file you get from writing the words out, asserted with the doc
  comments stripped. Anything else is a call on a `const` receiver,
  `const $BrandEn().name`, which Dart canonicalizes: one method call, no
  allocation, no root pointer anywhere in the output.
* **A prediction disproved.** `architecture.md` had said, ever since the object
  graph was designed, that the `const` graph cost us linked translations, and
  that the feature would need a root reference when it arrived. It needed nothing: a `const` constructor
  with no fields is free to name from anywhere. Believing otherwise is why the
  feature waited, and the note now says so.
* **The target's parameters become yours**, merged through the existing
  `argument_kind_conflict` machinery rather than a second copy of it — so
  `{n, date}` here against a plural `n` there is an error, reported against the
  link, naming the message the other kind came from. Transitive, so a chain
  lends through.
* **Five new link codes and one for overrides**, registry at **101**:
  `unknown_link_target` with the nearest key offered, `link_cycle` with the ring
  written out in the order it is followed, `link_to_rich`,
  `rich_unsupported_link`, `invalid_link` (which is also what a `slang`-style
  relative `@:.sibling` gets, with the rule stated), and
  `override_contains_link`.
* **The cycle is the differentiator, and it was read in the sources.** `slang`
  throws a bare string for a missing target and guards rings only in the pass
  that gathers parameters, so two messages linking to each other emit code that
  calls itself; `easy_localization` resolves links at run time, one level deep,
  and its own source carries `// TODO: add recursion detection and a resolve
  stack.` Ours is an iterative DFS — a stack overflow in the checker looking for
  unbounded depth would be a joke at its own expense — and a ring copied into
  twelve files is one finding.
* **Validated per locale, before cross-locale validation**, because a
  translator can write a link too. A locale that writes the words out instead
  of linking produces the same signature and passes; a locale that drops the
  lent parameter is the ordinary `missing_placeholder`. The base locale is
  resolved first, so the one diagnostic points at the file the project is
  maintained in.
* **`runtime_overrides` decides the form**, and that decision is the only place
  the two features conflict: with overrides on a link is a call, so one bundle
  entry renames the product in every message that mentions it. Executed, not
  argued — `links_runtime_test.dart` installs `{'brand.name': 'Acme One'}` and
  reads three messages back, one of them Russian to show nothing else moved. The lent parameter is still a token a bundle can
  place; the linked text is not, because an override is the words of one branch.
* **A message reached only by a link is used**, so `unused` does not offer to
  delete it. The one direction that scan must never err in.
* **Six exhaustive switches broke, and the compiler named all six.**
  `LinkNode` is the first addition to `MessageNode` since the AST was written,
  and `rich_ast.dart` had predicted the cost exactly.
* **`nearest_key.dart`**: the edit-distance routine had grown two copies, and
  this would have been the third. One implementation now, behaviour unchanged.

### What this one leaves open

* **No relative links.** `slang`'s `@:.sibling` is refused with the rule stated
  rather than supported: every other place in this project names a key in full,
  and an anchor concept the model does not have would be one more thing for a
  key rename to get wrong.
* **No modifiers.** `easy_localization` has `@.upper:key`; a link brings the
  target's text as it stands. Case transformation is locale-sensitive in ways a
  build step should not guess at, and `toUpperCase()` on a Turkish `i` is the
  standard example.
* **The call form's cost was not separately benchmarked.** The inlined form
  needs no measurement — it is the same code a hand-written message compiles
  to — and the call form is visibly one method call on a canonicalized `const`,
  but neither is a number. Adding a benchmark case means adding a linked message
  to the example app, which is a change to a showcase for the sake of a figure
  nobody has disputed.
* **Nothing isolates what a link brings.** With `bidi_isolation` on, a link's
  text is not isolated, for the reason a nested choice's rendering is not: it is
  this locale's own words. But a link to a message that is nothing but a
  placeholder brings an interpolated value with it, and that value reaches the
  sentence unisolated — the bare-placeholder exception, seen from one more
  angle.
* **A link in a rich message is refused rather than supported.** Splicing a
  string into a span run would work; splicing one whose words a translator might
  later want to wrap in a tag would not, and the difference is invisible from
  the emitter. Refusing the half that happens to be expressible seemed better
  than shipping it.

## Milestone 32 — a release of bundles is one thing (done)

`check-overrides` took one file, so a twelve language rollout was twelve
invocations and twelve re-stamps. The directory form is not that loop with the
typing removed: three of its answers do not exist a file at a time.

* **Which locales have no bundle.** Printed by the command, not as a
  diagnostic: a locale nobody overrode keeps the text it compiled, which is
  correct, and is also the omission a rollout makes. Invisible while you name
  files one at a time, because the files you did not name are not in the
  question.
* **Two bundles claiming one locale** — `duplicate_override_locale`, the one new
  code, registry at **95**. An `en.json` left beside an `overrides_en.json`:
  both valid, both passing every per-file check, and which of them the
  application installs decided by whatever serves them. A bundle's locale comes
  from `@@locale` or from its file name, so the clash can be two declarations,
  two names, or one of each — tested as all three. The duplicate is still
  checked for everything else, because a report naming one of six mistakes
  costs six round trips whether the six sit in one file or in six.
* **Whether the set may be signed.** `--stamp` validates every bundle before it
  writes any. A release where some bundles carry a fingerprint and some do not
  is the worst state available — nothing on disk says which were checked — so
  one wrong Russian branch leaves all twelve unstamped and the report says so.
  Measured, not argued: the CLI test writes two bundles, breaks one, and
  asserts neither file gained a fingerprint.
* **The one file form is unchanged**, to the byte of its output: it keeps its
  two prose lines, because at that scale the fingerprint is a value somebody
  copies rather than a column. It runs the same two passes with one entry, so
  the forms cannot drift apart.
* **A fix the scale asked for.** `unknown_override_locale` pointed at the
  `@@locale` span, which is `null` for a bundle named after its locale — the
  normal shape in a directory of them. With one file you knew which file you
  named. It now falls back to the whole object, so every report says which file.
  Found by running the command, not by reading it.
* **Selection says its rule**: every `.json` directly in the directory, sorted,
  nothing below it. A `.json` that is not a bundle is an error naming the file
  rather than a skip, so `--from` at the wrong directory fails instead of
  passing over nothing. Probe 22 shows the duplicate, the zero fingerprints
  written, and then the same release signing as a whole.

### What this one leaves open

* **Nothing installs a directory at run time.** `installOverrides` is per
  locale on the generated enum, so an application that fetched twelve bundles
  makes twelve calls. That is the honest shape — each is checked against its own
  fingerprint — but an `installAll` taking a map of locale to bundle would be one
  call and one failure to handle.
* **Nothing serves bundles by fingerprint.** The build-time half is done; which
  bundle a running application is handed for its build is still the
  application's problem, and the mismatch exception is what makes getting it
  wrong visible rather than silent.
* **A locale with no bundle is a line, not a flag.** A release that *intends* to
  ship all twelve cannot ask the command to fail when one is missing; it reads
  the line, or counts the files itself. `--require-all-locales` is one flag and
  was not written, because nothing yet says how often a release is meant to be
  complete.
* **One directory, one project.** A monorepo with two applications and one
  translation service still runs the command once per project, which is right —
  the surface it checks against is one build's.

## Milestone 31 — a value cannot be reordered against its sentence (done)

The last thing the competitive review found that nothing here fixed, and the
one item on that list whose defect is invisible to every test a project is
likely to have.

* **Measured first, written second.** Eight cases were laid out with a
  `TextPainter`, with and without U+2068/U+2069, and the character positions
  read back. Five changed. For a Latin value in a Hebrew line: `Ada.` is laid
  out with the stop on the far side of the name, `3 Ada` comes out as `Ada 3`,
  and `-5%` as `5%-`. Every string comparison passes in each case, which is why
  this is found by a screenshot and not by a suite.
* **Three cases did not change**, and they are in the test too: a parenthesised
  Latin filename in a Hebrew sentence and a parenthesised Hebrew name in an
  English one are both already correct. A feature's limits are worth as much as
  its effect.
* **`bidi_isolation: true`** emits the two isolates around every placeholder
  that sits in text, in every locale — an embedded Hebrew name in an English
  sentence is the same problem from the other side. Two characters in a string
  literal, written as `\u{2068}` escapes, so nothing is computed at run time and
  nothing in the generated file is invisible to a reviewer.
* **Three deliberate exceptions.** A message that is nothing but a placeholder
  is left alone — no text in that string to be reordered against, and the
  `String` passthrough stays an allocation free getter. The same placeholder
  alone in one span of a rich message *is* isolated, because the rest of the
  sentence is in its siblings. A nested choice's rendering is never isolated:
  it is this locale's own words, and the values inside it were isolated where
  they were interpolated.
* **Overrides compose with it.** The isolates go around the values handed to
  `fill`, not around the override's text, so a bundle gets them without knowing
  they exist. No key, branch or token name changes, so the Milestone 30
  fingerprint is unchanged and a stamped bundle stays valid — asserted, not
  assumed.
* **Off by default, and said once.** The isolates are invisible, so a test
  comparing a rendered message against a literal must carry them. Measured, not
  guessed: turning the option on in the Arabic evaluation application changes
  285 lines of generated code and breaks 9 of its 20 tests, all of them string
  comparisons. That trade belongs to the project, not to this library. A project with a right to left
  locale that interpolates anything gets `bidi_isolation_off`, naming the
  locale, the defect, the option and `ignore_diagnostics`. One more code, so the
  registry is at **94** — and the first suppressible code about something an
  option does *not* do.
* **The two tests are in two packages on purpose.** What the emitter writes is
  asserted in the generator's `bidi_isolation_test.dart`; what the characters
  *do* is asserted in the Flutter package's, with a real text painter. Two code
  points in a string were never the claim. Probe 21 shows the warning and then
  the wrapped literal.

### What this one leaves open

* **Nothing isolates the text an override supplies**, only the values put into
  it. A bundle whose own words mix directions is the translator's business, and
  there is no build step that could know.
* **The option is all or nothing per project.** A team that wants isolation in
  Hebrew and not in English has to take both.
* **No runtime helper to strip the isolates**, so a test that compares a
  rendered message against a literal writes them itself. A one-line
  `String.replaceAll` in the project's test helpers is the whole workaround,
  and it seemed better than an API.
* **The evaluation corpus is left as it was.** `evaluation/marketplace` has an
  Arabic locale and now reports `bidi_isolation_off`, which is the warning
  landing on exactly the kind of application it was written for — a realistic
  one, built before the option existed. Turning it on there is the 285 line, 9
  test measurement above, and the corpus is meant to be a sample rather than a
  showcase.

## Milestone 30 — a bundle says which build it is for (done)

The hole Milestone 29 left open, and the only one of its four that could ship
wrong text with every check passing.

* **The defect.** A nested choice is addressed by position: `0/one` is the `one`
  branch of a message's first nested choice, `{#0}` is that choice's rendering
  in the text around it. A release that puts another plural ahead of it moves
  everything after it, and every name in the old bundle still exists — so
  `check-overrides` passes and the words of one choice become the words of
  another. Reproduced on a real project before writing anything:

  ```
  compiled:  You have 1 wallet with 1 card linked
  installed: You have 1 saved card with 1 card linked
  ```

* **The fix.** `check-overrides --stamp` writes the surface it checked into the
  bundle as `@@fingerprint`, and the generated
  `AppLocale.ru.installOverrides(bundle)` carries this build's own as a constant
  and throws `L10nOverrideMismatch` for any other, installing nothing. The
  application keeps rendering what it compiled, which is the correct text for
  the build that is running.
* **What it covers is what can change meaning:** the keys, each message's
  slots, the tokens each slot substitutes, and the argument each choice selects
  on. Not the text — a reword is the release an override exists to avoid waiting
  for. Not the language's CLDR categories either, though the branch check reads
  them: an upgrade that leaves the emitted branches alone leaves every bundle
  correct, and a false refusal costs an application its live text. Nothing in it
  depends on order except the numbering of the nested choices, which is the case
  it exists for.
* **Coarse on purpose.** One value per locale, so a release that adds a message
  invalidates that locale's bundles although their entries are all still valid.
  The exact alternative is a hash beside every string in a file a translator's
  tooling carries; this one costs a `--stamp` in a release that had to re-check
  its bundles anyway.
* **It identifies, it does not authenticate.** FNV-1a, 64 bits, 16 hex digits,
  20 hand-written lines and no new dependency. Anybody who can replace the
  bundle can replace the fingerprint in it; the download's integrity is TLS's.
* **The runtime still installs an unfingerprinted bundle.** The check refuses
  one, with the line to paste, because that is where this project refuses
  things. The runtime does not, because its job is never to make a running
  application worse, and because `install` is also what a test calls. Build time
  decides what may ship; run time decides what is safe to do with what shipped.
* **`L10nController.installOverrides` is gone.** It was sugar for the store, and
  the fingerprint is not reachable through the `AppLocaleBase` bound, so it
  would have had to take the hash as an argument — longer than the call it
  saved. The repaint never depended on it: the controller subscribes to the
  store, not to a method of its own.
* **Two more codes**, so the registry is at **93**:
  `missing_override_fingerprint` and `override_fingerprint_mismatch`. Probe 19
  now asks for a stamp on a bundle with a bad branch and does not get one; probe
  20 stamps a good bundle, moves a choice and is refused.
* **Nothing in the hot path.** The comparison happens once, at install, so the
  generated message bodies are unchanged and the benchmark is where it was: 3.7
  ns for a getter, 5.8 with an empty store, 28.8 with a bundle installed.

### What this one leaves open

* **A fingerprint is per locale, so a twelve-language rollout re-stamps twelve
  files.** Still true, and it has to be: the locale tag is inside the value.
  ~~And `check-overrides` still takes one file at a time, so that is twelve
  invocations.~~ **Closed in Milestone 32** — `--from` takes the directory, one
  run re-stamps all twelve, and all twelve wait on the last of them.
* **Nothing serves bundles by fingerprint.** It is the natural cache key for a
  CDN path, and saying so in the README is as far as this goes.
* **An unfingerprinted bundle is still installable**, deliberately, as above. A
  project that wants it refused has to refuse it in the code that fetches.

## Milestone 29 — translations change without a release (done)

The one item the competitive review called worth more than everything else on
the behind list, and the only one that needed a runtime path alongside the
generated one.

* **The split.** The generated code keeps every decision — the plural category
  is chosen by the CLDR rules compiled to Dart, each argument is formatted
  through `package:intl` — and an override supplies **the text of one branch**,
  with `{name}` and `#` holes that the already-formatted values are substituted
  into. The alternative, evaluating downloaded ICU at run time, would have put a
  second and unverified copy of CLDR into the package that has no dependencies,
  to replace the one thing this library does better than the field.
* **`runtime_overrides: false` by default**, and with it off nothing is emitted:
  every existing golden is byte for byte what it was, asserted by the golden
  tests rather than assumed. On, the store costs 1.8 ns on the cheapest message
  read with nothing installed, and 28.5 ns with a bundle that does not carry the
  key.
* **`check-overrides`.** OTA moves a class of error back to run time, in a
  library whose whole argument is the opposite, so a bundle is validated against
  the project first — ten error codes then, twelve now, and the one that
  matters is a branch name
  checked against the categories of *that choice*: `two` is wrong in an English
  cardinal plural and right in an English ordinal, `one` is right for a Russian
  cardinal and wrong for a Russian ordinal. Probe 19 replays it. At run time
  nothing throws and an unknown token stands in the string, because a wrong
  override must not crash an app that is already shipped.
* **An override cannot change the API**: no new key, no placeholder added or
  dropped, no new branch. Those are a release. A rich message cannot be
  overridden at all — spans are structure, not text.
* **No HTTP.** Fetching, caching, credentials and retry are the application's;
  `installOverrides` takes a map and notifies, so the screens reading
  translations repaint.
* **Ten more codes**, taking the registry to **91** (and 93 after Milestone
  30): `invalid_override`,
  `unknown_override_locale`, `unknown_override_key`, `unknown_override_branch`,
  `unknown_override_placeholder`, `override_needs_branches`,
  `override_takes_no_branches`, `override_unexpected_number_sign`,
  `override_contains_icu`, `override_rich_unsupported`.

### Two predictions this disproved

1. **`setLocale` does not become asynchronous.** Both this roadmap and the
   review said OTA would be the feature that made it async. It is not: the fetch
   happens in the application's code, before the install, and the install is a
   map assignment. The prediction assumed the library would do the fetching, and
   the library has no business doing it.
2. **The runtime did not need a map path "alongside the generated one"** in the
   sense meant here — a parallel lookup structure the generated accessors fall
   back to. What it needed was a lookup *inside* each accessor, which is a
   smaller thing and leaves the `const` graph intact.

### What is still open after it

* ~~**No bundle fingerprint.**~~ **Closed in Milestone 30.**
* ~~**`check-overrides` takes one file**, so a rollout in twelve languages is
  twelve invocations.~~ **Closed in Milestone 32.**
* **Untested combinations:** `fill_missing_from_base` together with overrides,
  and ARB or YAML sources with the flag on (the fixture is JSON).
* **Every install repaints every reader**, since the store does not say which
  locale changed.

## Milestone 26 — ecosystem


7. ~~**TMS import/export**~~ **half done in Milestone 28.** ARB and CSV travel
    both ways, which is the format every TMS accepts. What is left is the
    vendor side — a Crowdin, Lokalise or POEditor API instead of a person
    carrying the file.
8. **PO / XLIFF** interchange formats. Untouched.
9. ~~**OTA translations.**~~ **Done in Milestone 29**, and both halves of this
    prediction were wrong: no parallel map path (the lookup lives inside the
    accessor, and the `const` graph is intact) and `setLocale` is still
    synchronous, because the application does the fetching.
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
`architecture.md`. Both things this note used to list as unmeasured were
measured in Milestone 24: `context.l10n` costs 44 ns against 6 ns for a direct
call, and a locale switch over 200 widgets is 7.4 ms — Flutter's
`dependOnInheritedWidgetOfExactType` and Flutter's rebuild, as predicted.
Milestone 29 added the override store's 1.8 ns.
