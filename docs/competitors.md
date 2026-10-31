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
| CSV input | N | Y (incl. one file for all locales) | N | ~ (add-on) |
| Formats mixable in one project | **Y** | N | N | N |
| Nested keys | Y | Y | **N** | Y |
| Namespaces across files | Y | Y | **N** (open since 2022, 128 reactions) | ~ |
| CLDR cardinal plurals | **Y — 222 languages** | ~ **14 hand-written**, rest silently wrong | Y — 119 via `package:intl` | **N — CLDR off by default** |
| Ordinals | **Y — 107 languages** | ~ 14 | **N** | N |
| Plural rules independently verified | **Y — vs `intl` and an ICU dump** | N | (is the oracle) | N |
| Several plurals in one sentence | N | **Y** (linked translations) | N | N |
| Select / gender | Y — generated enum | Y — generated enum | ~ `String`, case-sensitive, silent fallthrough | ~ free string |
| Typed placeholders | Y | Y | Y | **N** |
| Named arguments | Y always | Y always | ~ opt-in | n/a |
| Non-nullable accessor | Y | Y | ~ nullable by default | n/a |
| Number / date / currency | Y — 11 styles + skeletons | Y | Y — 41 `DateFormat` variants | ~ re-exports `intl` |
| Rich text / `TextSpan` / links | **N** | Y | N | N |
| Lists, maps, dynamic key access | **N** | Y | N | Y (keys are strings) |
| Linked translations `@:` | **N** | Y | N | Y |
| Interfaces / polymorphic subtrees | **N** | Y | N | N |
| Fallback chain configurable | Y | Y | ~ always the template locale | Y |
| Region affinity (`en_NZ` → ?) | ~ **alphabetical accident** | Y (`en-GB` → `en` always) | Y | ~ |
| Partial locales | Y | Y | Y | ~ |
| **Build fails on a missing translation** | **Y — diagnosed, with warn mode** | Y — as a Dart compile error | **N — `printStatus` only, no flag exists** | N |
| Build fails on an extra key | **Y** | N | N | N |
| Rename detection | **Y — unique in the field** | N | N | N |
| Diagnostic codes + per-code suppression | **Y — 71 codes** | N | ~ all-or-nothing | N |
| Cross-locale placeholder / arity check | **Y** | ~ | ~ (and has open bugs) | N |
| Unused-key analysis | Y (text scan) | Y (+ `clean`; false positives) | **N** | N |
| Write missing keys back to source | N | Y (`apply`) | N | N |
| Extraction from source | N | ~ (`$wip apply`) | N | N |
| CLI command count | 3 | ~12 | 1 | 2 |
| Watch mode | Y | Y | **Y, inside `flutter run`** | n/a |
| Lazy / deferred per-locale loading | **N** | Y (default on) | ~ opt-in, web | N |
| Over-the-air / runtime overrides | **N** | Y | N | ~ 23-line loader, no cache |
| Asset obfuscation | N | Y | N | N |
| Typed locale enum + typed switching | Y | Y | **N** | ~ |
| Works without `BuildContext` | Y (`forLocale` / `of`) | Y (static `t`) | ~ undocumented | Y |
| Ambient "current translations" | **N** (deferred on purpose) | Y | N | Y |
| Pure-Dart / server | Y | Y | **N** | N |
| Deterministic, diff-stable output | **Y — byte-identical, formatted** | **N** — `Built on` timestamp dirties git; flat map causes merge conflicts | ~ | n/a |
| `const` namespace accessors | **Y — allocation-free, 3.8 ns** | N (`late final`, open request) | ~ | n/a |
| Generator is `dev_dependencies` only | **Y** (runtime has zero deps) | **N** — `yaml`, `watcher`, `serial_csv` ship in app deps | Y (`intl` only) | N |
| Material / Cupertino widget strings | N — you add `flutter_localizations` | ~ | **Y — 115+ locales built in** | ~ |
| TMS integration | ~ tolerates a TMS ARB export | ~ CSV, Weblate docs, MCP | **Y — ARB is the universal format** | ~ |
| RTL helpers | **N — zero mentions in the repo** | N | Y (framework delegate) | ~ |
| Published, community, Stack Overflow | **N** | Y | Y | Y |

Counting the `Y` cells on the 45 comparable axes: **`slang` ≈ 31, `l10n_plus`
≈ 24, `gen_l10n` ≈ 15, `easy_localization` ≈ 10.** So "more features than the
competition" is true against the official tool and against every runtime
package, and false against `slang`.

---

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

## 5. Where we are behind, in priority order

1. **No over-the-air anything.** `slang` has `overrideTranslations`,
   `i18n_extension` has `byHttp` with typed errors and a never-throws
   guarantee, `flutter_i18n` has network and device-filesystem loaders, and
   `rerune` (2026) overlays remote strings under generated accessors. This is
   the one axis where runtime designs win architecturally, and our roadmap is
   explicit that it needs a runtime map path and an async `setLocale`.
2. **No rich text.** `(rich)` → `TextSpan` with per-placeholder callbacks is a
   `slang` feature with no equivalent anywhere else, and bold-or-a-link inside
   a sentence is an ordinary product requirement. `gen_l10n` has an open issue
   for it, so this is a gap against `slang` only.
3. **No linked translations**, therefore no two plurals in one sentence —
   something ICU itself cannot do and `slang` can.
4. **No lazy loading.** `slang` defers per-locale imports by default; at
   810 messages × many locales this is a web bundle-size argument we currently
   lose.
5. ~~**Region affinity is an alphabetical accident**~~ **Fixed, and the claim
   above was half wrong.** A bare `en` already won — the lineage walk ends at
   the language — so `slang`'s `en-GB` → `en` guarantee was one we also kept,
   by accident rather than on purpose. The real defect was narrower and worse:
   with no bare `en`, the winner was whichever sibling the supported list named
   first, so renaming a translation file changed what the app rendered. Siblings
   are now ordered by script agreement (`zh_Hant_HK` reads as `zh_Hant_TW`, not
   `zh_Hans_CN`) and then by tag. Still no CLDR affinity table, and still said
   out loud.
6. **No CSV, no PO/XLIFF, no TMS integration**, and ARB support is tolerance
   rather than a workflow. ARB-as-input is what buys the whole translation
   vendor ecosystem.
7. **Thin CLI**: 3 commands against `slang`'s ~12 (`apply`, `normalize`,
   `edit`, `stats`, `migrate`, `clean`, `configure`, `$wip apply`).
8. **No maps, lists or dynamic key access**, so server-driven copy
   (`tr('error.$code')`) is structurally impossible — a genuine advantage of
   every string-keyed package.
9. **Nothing for RTL** — zero occurrences of `TextDirection`, `Directionality`
   or bidi isolation in the repo. Worse, `fill_missing_from_base` fills an RTL
   locale with LTR base text, formatting included.
10. **No ambient context-free accessor** (deferred deliberately, with a good
    reason, but every competitor has one), **no IDE plugin**, **no hot-reload
    claim**, and **nothing published on pub.dev** — no community, no Stack
    Overflow answer, no name.

## 6. The three things that would make the claim true

- **Rich text** closes the biggest product-shaped hole against `slang`.
- **Runtime overrides over the generated accessors** (the `rerune` shape: new
  keys and changed signatures still need a release, copy changes do not) answers
  the whole runtime tier at once.
- **ARB round-tripping plus a `diff`/`apply` pair** turns the strictness story
  into a translator workflow instead of a wall.

And one that costs nothing: `slang` leaves CLDR plurals wrong for ~100
languages while advertising the feature. That is the sentence our README should
open with, because it is checkable and nobody else can say it.
