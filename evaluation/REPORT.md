# l10n_plus, evaluated by building four applications

Method: build applications, run them, read the real output, and make mistakes
on purpose. Nothing below is an impression — every claim names the project,
the command and the output it came from. Anything I could not reproduce is not
here.

Baseline at the start of the session: `dart analyze` clean, 410 package tests,
20 example tests.

**This is a snapshot, not a status page.** It records what was true when the
four applications were built, at Milestones 19 and 20: CLDR tables at 74
languages, 553 package tests, sixteen probes. Later milestones moved all
three. The figures as they stand are at the end, under
[Verification](#verification); `README.md` and `docs/roadmap.md` carry the
rest.

---

## Summary

The core is right. Plural selection, ICU semantics and number and date
rendering all agree with `package:intl` computed independently, in every
language I checked, including the ones that break naive implementations. Code
generation is deterministic and the generated code is analyzer clean at 810
messages.

The defects I found were all at the edges: one wrong CLDR rule per hundred,
two combinations of options nobody had run together, and an exit code that
made CI blind to a configuration error. Eleven of them are fixed here, with
tests. What remains is documented at the bottom.

Cost to a newcomer: three files and one command to a working screen, and I
needed the README twice for things it did not say.

---

## What works

### Plural selection is correct, and now provably so

`evaluation/marketplace` renders one message in five languages with five
different plural systems. Every value below is real program output, from
`dart run bin/catalog.dart`:

| count | `ar` | `pl` | `sl` | `ja` |
| --- | --- | --- | --- | --- |
| 1 | مراجعة واحدة (one) | 1 opinia (one) | 1 mnenje (one) | レビュー 1件 |
| 2 | مراجعتان (two) | 2 opinie (few) | 2 mnenji (**two**) | レビュー 2件 |
| 3 | 3 مراجعات (few) | 3 opinie (few) | 3 mnenja (few) | レビュー 3件 |
| 5 | 5 مراجعات… (many) | 5 opinii (many) | 5 mnenj (other) | レビュー 5件 |
| 11 | 11 مراجعة (many) | 11 opinii (many) | 11 mnenj | レビュー 11件 |
| 21 | 21 مراجعة (many) | 21 opinii (**many**) | 21 mnenj | レビュー 21件 |
| 101 | 101 مراجعة (other) | 101 opinii | 101 mnenje (**one**) | レビュー 101件 |
| 102 | 102 مراجعة (other) | 102 opinie (few) | 102 mnenji (**two**) | レビュー 102件 |
| 103 | 103 مراجعات (**few**) | 103 opinie | 103 mnenja | レビュー 103件 |
| 1.5 | 1.5 مراجعة (other) | 1,5 opinii (other) | 1,5 mnenja (**few**) | レビュー 1.5件 |

The bolded cells are the ones an implementation that looks at the last digit
gets wrong. Arabic's `few` wraps at 103 because the rule is `n % 100 = 3..10`;
Polish 21 is `many`, not `one`; Slovenian keys on `i % 100`, so 101 is
singular and 102 is a dual; a Slovenian fraction is `few`, not `other`.

Japanese declares only `other` and the generator accepted that without asking
for a `one` branch. English declaring only `other` was caught:

```
warning[missing_plural_category]: Plural "count" does not define one for en.
  en uses: one, other.
  Those counts will fall back to the "other" branch.
```

That warning found a real bug in my own English file within the first minute
of writing it.

**I did not take this on trust.** `package:intl` carries its own copy of the
CLDR rules, generated from ICU data, so it is an independent oracle. The new
`packages/l10n_plus_generator/test/plural_matrix_runtime_test.dart` generates
one message per supported language, executes the generated code, and compares
every branch against `Intl.pluralLogic(..., useExplicitNumberCases: false)`
over ~90 sample values — integers, teens, round tens, the 100..103 boundary,
whole millions, and fractions. 74 languages × 90 samples.

That test found four wrong rules. See "What was broken".

**Ordinals get their own oracle.** `intl` ships no ordinal table, but ICU does,
and `Intl.PluralRules(locale, {type: 'ordinal'})` in Node is it.
`tool/derive_ordinal_oracle.mjs` dumps ICU's answer for 1214 values per
language into `test/data/cldr_ordinals.json`, and
`test/ordinal_matrix_runtime_test.dart` executes the generated ordinal matrix
against the dump. The answers are vendored, not queried, so the suite still
needs nothing but Dart. Real output from `evaluation/fintech`: `1st, 2nd, 3rd,
4th, 11th, 12th, 13th, 21st, 101st, 111th` — the ordinal table, not the
cardinal one.

### The numbers are `intl`'s numbers

Every numeric assertion in `evaluation/fintech/test/statements_test.dart` and
`evaluation/marketplace/test/catalog_test.dart` compares against
`NumberFormat`/`DateFormat` constructed directly in the test rather than
against a literal I typed. They all pass. Concretely, from
`dart run bin/statement.dart`:

```
en:  Opening balance: USD1,234.50     Closing balance: $9,876.54
ru:  Входящий остаток: 1 234,50 USD   Исходящий остаток: 9 876,54 $
ja:  カード残高: $1,235                 (simpleCurrency, decimalDigits: 0)
en:  ₿0.01250000 in the vault          (BTC, symbol, 8 fraction digits)
```

`currency` prints the code, `simpleCurrency` the symbol, the amount always
keeps the rendering locale's separators, and a locale may restyle what the
base declared while inheriting its currency and digits. Compact numbers are
genuinely the locale's: Japanese compacts on 万 (`1.23万`), English on K
(`12.3K`), Polish on `tys.`.

Two things I expected to be wrong and were not: `integer` rounds *and* groups
(`1234.56` → `1,235`), and `percent` rounds to whole percent by default
(`0.015` → `2%`) — both are `intl`'s behaviour, faithfully delegated.

### The runtime really is Flutter free

`evaluation/fintech` and `evaluation/tms` are plain Dart packages with no
Flutter dependency at all, running under `dart run` and `dart test`. They
import `l10n_plus` (zero dependencies) and `intl` only because they format.
`flutter.enabled: false` in the config is the whole difference.

### `file_per_locale` does what it promises

`evaluation/bigapp`: 810 messages, 27 translation files, 9 namespaces,
4 locales. Changing one Russian word:

```
unchanged lib/l10n/app_l10n.g.dart
unchanged lib/l10n/app_l10n_de.g.dart
unchanged lib/l10n/app_l10n_en.g.dart
wrote     lib/l10n/app_l10n_ru.g.dart
unchanged lib/l10n/app_l10n_flutter.g.dart
```

One word, one file, 1.0 s. Full generation of all 810 messages: 2.4 s.
Generating twice produces byte identical output (`shasum` compared), and the
CLI distinguishes `wrote` from `unchanged`, so a no-op regeneration does not
touch mtimes.

### `{namespace}_{locale}` scales

Nine teams owning `auth_en.json`, `wallet_en.json`, … and never repeating the
feature name inside the file. Nothing about the generated API says which file
a key came from. Two files of one locale defining the same key is an error
that names both files.

### Diagnostics mostly hold up

Sixteen deliberate mistakes are in `evaluation/probes/probe.sh`, with the
output in `transcript.txt`. The ones that impressed me:

*A missing subtree collapses.* Adding a fourth locale with one key to an app
with 270 gave 17 errors, not 269 — it reports the highest missing node rather
than every leaf under it.

*The base locale file is named.* A rename in one locale produces `missing_key`
and `extra_key` pointing at both the file and the line.

*Config typos.* `file_per_local` gets `unknown_config_key` with the full list
of known keys.

*Collisions.* `user_name` and `userName` colliding after normalization, and a
key called `appLocale` colliding with the generated accessor, are both errors
that name the collision and the fix.

*A language with no rules.* `cy` gets `unknown_plural_language` listing every
supported language, rather than silently borrowing English's.

Every one names file, line, column, key, code, what was expected and what was
found. That claim in the README holds.

---

## What was broken

All eleven are fixed in this session, each with a test that fails without the
fix. Order is by how much damage they could do.

### 1. Seven wrong CLDR plural rules

Found by the new differential test against `package:intl`.

| Language | Symptom | Cause |
| --- | --- | --- |
| `ar` | `3.5` selected `few`, ICU says `other` | UTS #35 ranges match integers only; the condition was compiled as `n % 100 >= 3 && <= 10` with no integer guard |
| `he` | `0.5` selected `other`, ICU says `one` | `one` was missing its `i = 0 and v != 0` clause |
| `ro` | `101`, `201`, `1001` selected `other`, ICU says `few` | the range was written `n % 100 = 2..19`; CLDR says `n != 1 and n % 100 = 1..19` |
| `es` `fr` `it` `pt` | `1000000` selected `other`, ICU says `many` | CLDR 38 gave the Romance languages a `many` for whole millions ("1 million **de** livres"); the table predates it |
| `en` ordinal | `1.5` selected `one`, ICU says `other` | the rule was written over the operand `i`; CLDR writes English's ordinal over `n` |
| `vi` `ms` ordinal | every value selected `other` | both were listed as having no ordinal categories; CLDR gives each a `one` |

The Romanian one is the worst of the four: `101` is a number a shopping cart
sees, and the wrong branch is grammatical nonsense rather than an obvious
bug. The Arabic one is the subtlest: it only shows on fractions.

Note the reverse direction — `fr(1.5)`, `pt(1.5)`, `da(1.5)`, `hi(0.5)` — is
`intl` being wrong, not this library. `intl` computes the operand `i` as
`n.round()` where CLDR defines it as the integer digits of `n`, so it reads
1.5 as `i = 2`. The table is right; the test documents the oracle's defect
and asserts those values by hand.

### 2. `file_per_locale` + `fill_missing_from_base` produced a library that did not compile

The two options had never been used together. A filled message is the base
locale's message, formatting included, so an untranslated French date reaches
for `_enDateYMMMd`. The emitter assigned formatters to a part file by "what
this file uses", so the same top level final was declared in two parts of one
library:

```
lib/l10n/app_l10n_fr.g.dart:5:18: Error: '_enDateYMMMd' is already declared in this scope.
```

Found by `flutter test` in `evaluation/bigapp`, not by any golden. Fixed by
assigning each formatter to the locale it formats **for** rather than the
locale that uses it, which required carrying `localeDartName` on
`FormatterBinding`.

### 3. A select branch named `values` or `index` generated an enum that did not compile

```
{"a": "{s, select, values{V} index{I} other{O}}"}
```
generated
```
enum AS { values, index, other }
```
which is `values_declaration_in_enum` and `conflicting_static_and_instance` —
and no diagnostic said so. The escaping mechanism existed (`hashCode$`,
`toString$`) and simply did not know about the two names every enum declares
itself. Fixed with an enum specific reserved set, so a message called `index`
is still `index` while a *branch* called `index` becomes `index$`. The
`json` and `yaml` golden fixtures now contain such a select, so `dart analyze`
proves it compiles.

### 4. A configuration error exited zero

```yaml
format_plural_numbers: "yes please"
```
```
error[invalid_config]: "format_plural_numbers" must be true or false.
wrote lib/l10n/app_localizations.g.dart
$ echo $?
0
```

The README says `analyze` "exits non-zero on any error". It did not, for
config errors: `L10nPlusConfig.parse` reports the bad value and carries on
with the default, and the CLI decided the exit code from the *generator's*
diagnostics only. CI would pass on a project generating from a configuration
it had already called wrong. The `build_runner` adapter was already correct,
because it passes one collector through; the fix makes `run()` accept the same
collector, so the two entry points agree. Covered by
`test/cli_exit_code_test.dart`, which runs the CLI as a process — the exit
code lives in `bin/` and no in-process test reached it.

### 5. A diagnostic printed `null`

```
error[plural_type_mismatch]: Argument "n" is a null here but a selectordinal in the base locale.
```

`pluralType` is null when the argument is not a plural at all. Now "a plain
number".

---

## What was improved

### The CLDR table went from 37 languages to 74

Slovenian was my first attempt at a fifth language in the marketplace app,
and it was a hard stop: `unknown_plural_language`, no output, no escape hatch.
The design decision behind that — never silently borrow English's rules — is
right, but the coverage made it a wall. Missing were Bulgarian, Catalan,
Slovenian, Latvian, Lithuanian, Persian, Bengali, Urdu, Icelandic, Albanian,
Macedonian, Afrikaans, Swahili, Filipino, Tamil, Telugu, Malayalam, Kannada,
Marathi, Gujarati, Khmer, Burmese, Lao, Nepali, Sinhala, Kazakh, Kyrgyz,
Uzbek, Mongolian, Armenian, Belarusian, Galician, Basque, Amharic, Zulu.

Hand transcribing 37 languages' plural rules into a library whose whole point
is not shipping wrong plurals would normally be a bad trade. With the
differential test it is not: I wrote them, ran the oracle, and it rejected
three of them (`is`, `kn`, `mr`) with the exact sample that disagreed. All 74
now agree with ICU data on every sample.

### Ordinals went from 36 languages to 74, the same set

The first pass left 38 languages able to count things but not to number them,
and I said the blocker was the oracle. It was, and it exists: ICU, through
Node's `Intl.PluralRules(locale, {type: 'ordinal'})`. Dumping its answers for
1214 values per language and vendoring them gave the ordinal table the same
kind of check the cardinal one now has, and it found three defects among the
36 entries that were already there (`en`, `vi`, `ms`, above).

It also surfaced something I would have got wrong by hand in three languages:
**CLDR writes some ordinal rules over `n` and some over `i`**, per language,
and the difference is observable. English `1.5` is `other` because its rule
reads `n % 10 = 1`; Azerbaijani `1.5` is `one` because its rule reads
`i % 10 = 1`. Both are meaningless input — there is no 1.5th of anything — but
they are ICU's answers, and matching them costs nothing.

I checked the guard rather than trusting a suite that passed first time:
putting the English rule back on `i` fails the differential test with exactly
`en(1.5): ours=one icu=other` and nothing else.

`evaluation/marketplace` now has its `selectordinal` back. It had to be
deleted mid-evaluation because Slovenian could not generate one; Slovenian
now renders `Vaše 1. naročilo` through `Vaše 101. naročilo` while still
distinguishing four cardinal forms.

### Diagnostics at scale

Two changes driven by the 810 message app:

*A collapsed subtree says how big it is.* "Key `wallet` is not translated in
fr" could stand for one message or three hundred:

```
Base locale en defines it at wallet_en.json:1. It covers 30 messages.
```

*The base file is named.* "Base locale en defines it at line 4" names nothing
once `file_pattern` spreads a locale over nine files.

### The generated library now stands on its own

`AppLocalizations.of` takes an `L10nLocale` and `appLocale.l10nLocale` returns
one, but the generated file imported `package:l10n_plus` without exporting it.
The README's own snippet —

```dart
import 'generated/app_localizations.g.dart';
...
final u = AppLocalizations.of(L10nLocale.parse('pt_BR'));
```

— did not compile. It now does; the generated header carries
`export 'package:l10n_plus/l10n_plus.dart' show L10nLocale;`.

The README's Flutter usage section also showed one import where an app needs
two — the Flutter glue is a separate library — and never mentioned
`flutter_localizations`. Building `bigapp` produced six undefined symbols and
then "No MaterialLocalizations found" at runtime. Both are now in the README.

---

## How hard is it to use

### Cold start

Three files (`pubspec.yaml`, `l10n_plus.yaml`, `translations/en.json`) and
`dart run l10n_plus_generator generate`. For `evaluation/fintech` that was
about four minutes including reading the config options. The first thing that
went wrong was my own missing `one` branch, and the diagnostic explained it
without a trip to the docs.

I opened the README twice for things it did not say (both now fixed): the
second import for Flutter, and that `L10nLocale` needed its own import.

Guessing at ARB was cheap. `"type": "DateTime"` with `"format": "yMMMM"` —
the standard `gen_l10n` spelling — worked unchanged, as did
`optionalParameters` with `name`, `symbol` and `decimalDigits`. An
unedited TMS export with flat dotted keys generated a nested API with
`file_pattern: "intl_*{locale}"` and nothing else.

### Where it hurts in week two

**~~A rename is 2N errors with no hint that it was a rename.~~ Fixed.**
Renaming `auth.login.title` to `headline` in the base locale produced, per
locale, one `missing_key` and one `extra_key`; neither said "these two look
like the same rename". A namespace with exactly one missing and exactly one
extra key of the same kind now gets a single `renamed_key` naming both sides
with their files and lines. On the four locale app: six errors became three,
one per language that lags. Two of each is still reported separately, because
that could be two renames or four unrelated edits.

**~~`unused` is structurally blind to the naming large apps use.~~ Fixed.**
On the 810 message app it reported "No unused keys. 270 checked" while the app
referenced eight of them: the scan matched the leaf member name, and a
conventional `feature.group.title` / `.subtitle` / `.action` scheme uses each
of those words on the first screen. It now requires every name on a key's path
to appear, which is safe for the same reason the old rule was — each step has
to be named to be taken — and reports 234 of 270 on that app, collapsed into
19 findings.

**A partially translated locale renders base locale *formatting*, not just
base locale words.** In `evaluation/tms`, Spanish shows
`Due on Apr 30, 2026` — English month name, English order — because the whole
message falls back. This is the documented and I think correct choice (it
looks untranslated rather than half translated), but it surprised me, and it
is worth knowing before turning the option on for a right-to-left or
CJK locale.

**~~No count of what is untranslated.~~ Fixed.** `analyze` on the partial
French rollout printed "0 error(s), 18 warning(s)" for 269 untranslated
messages. It now prints a per locale table — `fr 1/270 (0%, 269
untranslated)` — and only when something is incomplete.

**~~`ignored_placeholder_type` fires on the canonical `gen_l10n` spelling.~~
Fixed.** A real ARB bundle writes `"tone": {"type": "String"}` for a select
placeholder, which gen_l10n's schema requires. `String` and `Object` are now
silent; a declared `int` still warns, because that is an author who thinks the
argument is a number.

**~~`unknown_config_key` lists but does not suggest.~~ Fixed.**
`file_per_local` now gets "Did you mean file_per_locale?" ahead of the list.

**~~Forgetting `initialize<Class>Formatting()` fails with `intl`'s message.~~
Fixed.** Running it now gives "Date symbols for \"ru\" are not loaded. Call
`await initializeStatementsFormatting()` …", with intl's original error kept
underneath.

**~~Still no watch mode.~~ Fixed.** `generate --watch` rebuilds on a change
to a translation, the config or `pubspec.yaml`, re-reads the configuration
each time, and survives errors. Nothing else in the project is watched, so
saving a Dart file costs nothing.

---

## Verification

```
dart format . && dart analyze .     clean
dart test packages                  553 passed  (was 410)
cd example && flutter test           20 passed
```

Evaluation projects: 11 + 20 + 7 tests under `dart test`, 5 under
`flutter test`. Sixteen probes replayable with `evaluation/probes/probe.sh`.

The two plural tables are checked against 74 languages each: cardinals against
`package:intl` on ~90 samples per language, ordinals against a vendored ICU
dump on 1214.

Re-measured on 2026-10-31, after Milestones 21 to 25: `dart analyze` still
clean, 592 package tests and 29 example tests pass, `probe.sh` replays
eighteen mistakes, and the tables cover 222 cardinal and 107 ordinal
languages — every language CLDR publishes rules for, which is why the two are
no longer the same set.
