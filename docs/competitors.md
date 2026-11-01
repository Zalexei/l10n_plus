# Where `l10n_plus` stands against the alternatives

Researched 2026-10-31. Figures for other packages come from the pub.dev API
and each project's own source on that date; figures for `l10n_plus` come from
commands run against this working tree. Every row that says something is
missing was checked in the source, not inferred from a README.

The honest one-paragraph answer: **we are not the simplest and we do not have
the most features.** Setup cost is at parity with the best of the field, the
feature count is second to `slang`, and the advantage that is genuinely ours
is correctness and build-time strictness — plural rules for every locale,
diagnosed instead of silently approximated, with a build that refuses to pass
on a gap.

---

## 1. The field

| | `l10n_plus` | `slang` 4.19.2 | official `gen_l10n` | `easy_localization` 3.0.8 | `i18n_extension` 16.0.1 | `flutter_i18n` 0.37.1 |
| --- | --- | --- | --- | --- | --- | --- |
| Approach | typed codegen | typed codegen | typed codegen | runtime, string keys | runtime, English-as-key | runtime, string keys |
| Published | **not on pub.dev** | 2026-09-12 | ships with Flutter | 2025-07-24 | 2026-10-02 | 2025-12-18 |
| Likes | — | 794 | n/a | **3 843** | 374 | 204 |
| Downloads / 30 d | — | **378 994** | n/a | 333 933 | 79 930 | 28 467 |
| Maintenance | one author, pre-release | one author, Codeberg + stale GitHub tracker | Flutter team | owner: "not actively maintained", ~196 open | active, 5 open | quiet, 1 open |

Two corrections to the usual picture of this market:

- **`slang` is the competitor, not `easy_localization`.** It has more monthly
  downloads (379 k vs 334 k) and a perfect pub score, and it is the only
  package in the ecosystem whose feature set is larger than ours.
- **`intl_utils` / Flutter Intl is retired** (`isDiscontinued: true` on
  pub.dev as of 2026-10; the IDE plugins are dead too). Its ~343 k monthly
  downloads are a migration audience, not a rival.

---

## 2. Setup cost, measured

| | files touched | config | commands | widget-tree wiring |
| --- | --- | --- | --- | --- |
| `l10n_plus` | 3 | **1 line** (`base_locale`) | `dart run l10n_plus_generator generate` | `L10nScope` + a required inner `Builder`, ~10 lines, 2 generated imports, `await` init if any message formats a date |
| `slang` | 2 | **optional** | `dart run slang` | none required (static `t`); `TranslationProvider` only if you want rebuild-on-switch |
| `gen_l10n` | 3 | 3 lines | **none — runs inside `flutter pub get` / `flutter run` / hot reload** | delegates + `supportedLocales`, ~6 lines |
| `easy_localization` | 4 | n/a | none | `ensureInitialized()` + `EasyLocalization` wrapper + iOS `Info.plist` |
| `flutter_i18n` | 2 | n/a | none | one `LocalizationsDelegate`, nothing in `main()` |

Read that honestly:

- Against `gen_l10n` we win the code and lose the loop. Nesting, always-named
  arguments and a non-nullable accessor are a real daily improvement over
  `AppLocalizations.of(context)!.someFlatKey(positional)` — but `gen_l10n`
  regenerates *inside* `flutter run` and survives hot reload with no watcher,
  no second process and no dev dependency. That integration lives in
  `flutter_tools` and cannot be matched from outside it.
- Against `slang` we are not simpler. Its config file is optional, ours is
  mandatory; it needs no widget wiring to work, we need `L10nScope` plus an
  inner `Builder` because the scope is an `InheritedNotifier`.
- The runtime packages are cheaper to start and much more expensive later:
  no build step at all, but no compile-time key, no arity check, and a typo
  that renders `profile.settings.title` to a user.

One real trap of ours, found while writing this and since fixed:
**`flutter.enabled` defaults to `true`**, so a pure-Dart consumer following the
documented minimal config got a Flutter glue file it cannot compile — 16
analyzer errors and no diagnostic. It now reports `missing_flutter_dependency`,
naming the one line that turns the glue off. Pure-Dart cold start is still 3
config lines rather than 1.

---

## 3. Feature matrix

`Y` supported · `~` partial or caveated · `N` absent.

| Capability | `l10n_plus` | `slang` | `gen_l10n` | `easy_localization` |
| --- | --- | --- | --- | --- |
| JSON input | Y | Y | N | Y |
| YAML input | ~ (no metadata) | Y | N | ~ (add-on) |
| ARB input | Y | Y | Y (only) | N |
| CSV input | ~ (interchange only, not a build source) | Y (incl. one file for all locales) | N | ~ (add-on) |
| Formats mixable in one project | **Y** | N | N | N |
| Nested keys | Y | Y | **N** | Y |
| Namespaces across files | Y | Y | **N** (open since 2022, 128 reactions) | ~ |
| CLDR cardinal plurals | **Y — 222 languages** | ~ **14 hand-written**, rest silently wrong | Y — 119 via `package:intl` | **N — CLDR off by default** |
| Ordinals | **Y — 107 languages** | ~ 14 | **N** | N |
| Plural rules independently verified | **Y — vs `intl` and an ICU dump** | N | (is the oracle) | N |
| Several plurals in one sentence | **Y** — via links, each on its own count | Y (linked translations) | N | N |
| Select / gender | Y — generated enum | Y — generated enum | ~ `String`, case-sensitive, silent fallthrough | ~ free string |
| Typed placeholders | Y | Y | Y | **N** |
| Named arguments | Y always | Y always | ~ opt-in | n/a |
| Non-nullable accessor | Y | Y | ~ nullable by default | n/a |
| Number / date / currency | Y — 11 styles + skeletons | Y | Y — 41 `DateFormat` variants | ~ re-exports `intl` |
| Rich text / `TextSpan` / links | **Y — `(rich)` keys, a builder required per tag** | Y | N | N |
| Lists, maps, dynamic key access | **N** | Y | N | Y (keys are strings) |
| Linked translations `@:` | **Y — resolved at build time, parameters typed through** | Y | N | Y — at run time |
| A link cycle is a build error | **Y** — the ring named in order | N — guarded only while gathering parameters | n/a | N — `// TODO` in its own source |
| Interfaces / polymorphic subtrees | **N** | Y | N | N |
| Fallback chain configurable | Y | Y | ~ always the template locale | Y |
| Region affinity (`en_NZ` → ?) | ~ generic first, then script, then tag | Y (`en-GB` → `en` always) | Y | ~ |
| Partial locales | Y | Y | Y | ~ |
| **Build fails on a missing translation** | **Y — diagnosed, with warn mode** | Y — as a Dart compile error | **N — `printStatus` only, no flag exists** | N |
| Build fails on an extra key | **Y** | N | N | N |
| Rename detection | **Y — unique in the field** | N | N | N |
| Diagnostic codes + per-code suppression | **Y — 101 codes** | N | ~ all-or-nothing | N |
| Cross-locale placeholder / arity check | **Y** | ~ | ~ (and has open bugs) | N |
| Unused-key analysis | Y (text scan) | Y (+ `clean`; false positives) | **N** | N |
| Write missing keys back to source | ~ (`import`, from a hand-off file) | Y (`apply`) | N | N |
| Extraction from source | N | ~ (`$wip apply`) | N | N |
| CLI command count | 6 | ~12 | 1 | 2 |
| Watch mode | Y | Y | **Y, inside `flutter run`** | n/a |
| Lazy / deferred per-locale loading | **N** | Y (default on) | ~ opt-in, web | N |
| Over-the-air / runtime overrides | **Y — branch text, checked and fingerprinted at build time, per bundle or per release** | Y | N | ~ 23-line loader, no cache |
| Asset obfuscation | N | Y | N | N |
| Typed locale enum + typed switching | Y | Y | **N** | ~ |
| Works without `BuildContext` | Y (`forLocale` / `of`) | Y (static `t`) | ~ undocumented | Y |
| Ambient "current translations" | **N** (deferred on purpose) | Y | N | Y |
| Pure-Dart / server | Y | Y | **N** | N |
| Deterministic, diff-stable output | **Y — byte-identical, formatted** | **N** — `Built on` timestamp dirties git; flat map causes merge conflicts | ~ | n/a |
| `const` namespace accessors | **Y — allocation-free, 3.8 ns** | N (`late final`, open request) | ~ | n/a |
| Generator is `dev_dependencies` only | **Y** (runtime has zero deps) | **N** — `yaml`, `watcher`, `serial_csv` ship in app deps | Y (`intl` only) | N |
| Material / Cupertino widget strings | N — you add `flutter_localizations` | ~ | **Y — 115+ locales built in** | ~ |
| TMS integration | Y — ARB and CSV export/import | ~ CSV, Weblate docs, MCP | **Y — ARB is the universal format** | ~ |
| RTL helpers | **Y — direction per locale, warned when the fill crosses it** | N | Y (framework delegate) | ~ |
| Bidi isolation of interpolated values | **Y — `\u{2068}`/`\u{2069}` in the literal, opt in, warned about** | N | N | N |
| Published, community, Stack Overflow | **N** | Y | Y | Y |

Counting the verdicts over the 46 comparable rows — with
[`evaluation/tally.py`](../evaluation/tally.py), which is committed this time
and states its rule, so the number can be reproduced rather than taken on
trust:

```
python3 evaluation/tally.py
```

| | `Y` | `~` | `N` |
| --- | --- | --- | --- |
| `l10n_plus` | **35** | 4 | 8 |
| `slang` | **31** | 6 | 10 |
| `gen_l10n` | 12 | 10 | 25 |
| `easy_localization` | 8 | 12 | 27 |

This table has now been counted wrong twice. An early revision said
`l10n_plus ≈ 24` against `slang ≈ 31` by hand; four of those axes were closed
since (rich text, RTL, ARB/CSV interchange, region affinity) but the rest of
that gap was simply a miscount. Then the revision that replaced the hand count
published **32 against 31 over 46 rows** — which was also wrong, by one row in
every column: the table at that commit had 45 comparable rows, and the honest
figure was **31 against 31, a tie**. The bidi isolation row added in Milestone
31 is what makes it 32, so the number printed above happens to be the number
that was claimed a commit too early.

Which is the more useful finding, again, and why the script is in the
repository now: a comparison nobody can re-run is not a measurement, and a
script nobody keeps is nobody re-running it.

**Three of this revision's cells are one milestone's, and one of them is a row
we added.** Milestone 33 flipped "linked translations" and "several plurals in
one sentence" from `N` to `Y`, and introduced "a link cycle is a build error",
which no package but this one passes. Adding a row on the axis you have just
won is the easiest way to inflate your own total, so: without that row it is
**34 against 31 over 46 rows**, and with it **35 against 31 over 47**. The row
stays because whether a ring of links breaks the build or ships is a question a
user has, and because the two `N`s in it were read in the two packages' sources
rather than assumed — but the honest figure is the one without it.

**And four cells ahead is not a lead either.** A `Y` is not a unit of value: "asset
obfuscation" and "222 CLDR plural languages" are one cell each, and a table that
can be moved by picking different rows is a sketch of the field rather than a
verdict on it. What the two columns disagree about matters more than the total,
and it splits cleanly — `slang`'s remaining advantages are **runtime shape**
(lazy per-locale loading, an ambient accessor, dynamic key access, asset
obfuscation), ours are **build-time truth** (plural
correctness at 222/107 verified against two oracles, a build that fails on a gap
with 101 diagnostic codes, rename detection, byte-identical output, a dev-only
generator). Those are two different bets about where localization errors should
surface, not two scores.

Over-the-air used to be the clean example of their side of that split, and it is
the one axis where the two bets actually met: we took it by keeping the rules
compiled and shipping only branch text, and by making the bundle checkable at
build time — our bet applied to their feature, rather than theirs adopted.

## 4. What is genuinely ours

1. **Plural correctness at a coverage nobody else reaches.** 222 cardinal and
   107 ordinal languages, compiled from CLDR 48, differentially tested against
   two independent oracles (`package:intl`'s own CLDR copy for cardinals, an
   ICU dump from `Intl.PluralRules` for ordinals). The field for comparison:
   `slang` hand-writes **14** resolvers and silently uses a tolerant
   zero/one/other fallback for everything else — it logs an error and ships the
   wrong form; `gen_l10n` gets 119 locales right but has **no ordinals at all**;
   `easy_localization` ships with CLDR **disabled by default**, so Russian,
   Polish and Arabic are wrong out of the box and the maintainers declined to
   change it; `i18n_extension`'s modifier chain never consults the locale;
   `flutter_i18n` picks the largest numeric suffix ≤ the value, which cannot
   express an `n % 100` rule at all. One Russian unit test demonstrates this
   gap against every one of them.
2. **A build that refuses to pass on a gap, with something to read when it
   does.** 71 stable diagnostic codes, per-code suppression that cannot
   silence an error, real exit codes, spans and carets, and rename detection
   that names both files. `gen_l10n` cannot fail on a missing translation at
   all — a gap is a `printStatus` line and the template locale leaks to the
   user. `slang` fails, but as "missing concrete implementation" from the Dart
   compiler: no warn mode, no rename pairing, no extra-key policy.
3. **Output you can keep in git.** Byte-identical regeneration, `dart_style`
   formatted, no build timestamp, no single giant map literal. `slang` has open
   issues for exactly those two things.
4. **Weight and shape.** Runtime with zero dependencies, generator in
   `dev_dependencies`, `const` namespace accessors that allocate nothing
   (3.8 ns, re-measured). `slang` must sit in `dependencies` because its CLI
   and runtime are one package, so `yaml`, `watcher` and `serial_csv` land in
   every consumer's graph.
5. **Generated code is analyzed *and executed* against real `package:intl`** in
   the golden tests — which is how two shipped bugs were caught.

## 5. Closed since this document was written

Five of the ten gaps below are closed, each with tests that run rather than
assert the shape of the source. The fifth — runtime overrides, which this
document called worth more than everything else on the behind list — came last
and on its own, because it is the only one that touches the runtime:

0. **Runtime overrides.** A downloaded bundle replaces **the text of one
   branch**; the plural category is still chosen by the CLDR rules compiled into
   the app and every argument is still formatted by `package:intl`, so the
   runtime grew no parser, no rules and no dependency. `check-overrides`
   validates a bundle against the project before it ships, and validates a
   branch name against the categories of *that choice* — `two` is wrong in an
   English cardinal plural and right in an English ordinal. `slang` has
   `overrideTranslations`; it cannot check any of that, because it has 14
   hand-written plural resolvers rather than a table. An override cannot add a
   key or change a signature: those are a release.

   A checked bundle also carries **which build it was checked against**, because
   branches of a nested choice are addressed by position and a release that
   inserts one renumbers them while every name in the old bundle still exists —
   a bundle that passes every check and ships the words of one choice as the
   words of another. `check-overrides --stamp` writes the surface into the
   bundle and the generated `installOverrides` refuses any other, leaving the
   application on the text it compiled. No competitor has a fingerprint, and
   none of them has the slot table a fingerprint would be taken over.


1. **Rich text.** A key written `terms(rich)` yields a span list in the pure
   Dart file and, in the Flutter glue, a wrapper that **requires one builder per
   tag the message contains** — so a forgotten tag is a compile error, and the
   tag set has to agree across locales (`rich_tag_mismatch`). `slang` has the
   feature; it does not have that guarantee. A rich plural is refused rather
   than half-supported, because the guarantee only holds while the tag set is
   static.
2. **ARB and CSV interchange.** `export` writes every message with its base text
   and each locale's translation; `import` splices the answers back in at each
   leaf's value span, so key order, blank lines, YAML comments, indentation and
   line endings survive. Dry run by default. A round-trip test asserts the
   translation files come back **byte-identical** over JSON, YAML, ARB and a
   split layout, in both formats.
3. **RTL.** Direction per locale from CLDR's own two files, decided by script
   and never by region, `TextDirection` in the Flutter layer, and a warning for
   the case that made it worth doing: `fill_missing_from_base` substituting
   left-to-right base text into a right-to-left locale, which ships because the
   screen looks finished.
4. **Region affinity**, as described above: the generic locale first by
   guarantee, then script agreement, then the tag. No CLDR affinity table, and
   said out loud.

## 6. Where we are still behind, in priority order

1. **No lazy loading.** `slang` defers per-locale imports by default; at
   810 messages × many locales this is a web bundle-size argument we lose.
2. **No maps, lists or dynamic key access**, so server-driven copy
   (`tr('error.$code')`) is structurally impossible — a genuine advantage of
   every string-keyed package.
3. **No PO/XLIFF, and no vendor API.** ARB and CSV now travel; Crowdin,
   Lokalise and POEditor still mean a human in between.
4. **No extraction from source**, and `import` writes translations but never
   creates a file or a locale.
5. **Six CLI commands against `slang`'s ~12** (`edit`, `stats`, `migrate`,
   `clean`, `configure` have no equivalent here).
6. **No relative links or link modifiers.** `slang` has `@:.sibling`;
   `easy_localization` has `@.upper:key`. Both were refused with the reason
   written down rather than left unimplemented, which is a smaller gap than it
   was, but it is still theirs.
7. **No ambient context-free accessor** (deferred deliberately, with the
   footgun written down), **no asset obfuscation**, **no IDE plugin**, and no
   Material/Cupertino strings of our own.
8. **Nothing published on pub.dev** — no community, no Stack Overflow answer,
   no name. Unchanged by any of the above, and still the largest gap of all.

~~**No linked translations**, therefore no two plurals in one sentence.~~
**Closed in Milestone 33.** It was the first item on this list for every
revision of this document until then, and the reason it stayed there was a
belief about our own architecture rather than a difficulty: `architecture.md`
had said a link would need a root reference and so would cost the `const`
graph. It needed nothing — a `const` constructor with no fields is free to name
from anywhere.

## 7. The three things that would have made the claim true

Written before any of the work above. Two are now done:

- ~~**Rich text**~~ — done, with a compile-time guarantee `slang` does not have.
- ~~**ARB round-tripping plus a `diff`/`apply` pair**~~ — done as
  `export`/`import`, dry run by default. No `diff` command: a dry-run import
  *is* the diff, and a second name for it would have been a flag's worth of
  work pretending to be a feature.
- ~~**Runtime overrides over the generated accessors**~~ — done, in exactly the
  `rerune` shape this predicted: new keys and changed signatures still need a
  release, copy changes do not. All three are in, which means this list has
  nothing left on it and the next version of it has to be written from the
  current state rather than from this one.

And the one that costs nothing, still unspent: `slang` leaves CLDR plurals wrong
for ~100 languages while advertising the feature. That is the sentence the README
should open with, because it is checkable and nobody else can say it.
