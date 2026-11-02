# Evaluation projects

Four applications built to exercise `l10n_plus` by running it, plus a
replayable set of deliberate mistakes. Findings are in
[`REPORT.md`](REPORT.md).

Each project is a real pub package outside the workspace, with
`dependency_overrides` onto the local packages — the same shape a consumer
would have, minus pub.dev.

| Project | What it loads |
| --- | --- |
| `fintech/` | Server side Dart, no Flutter. Several currencies, `currency` against `simpleCurrency`, per locale fraction digits, ordinals, ARB metadata. `en`, `ru`, `ja`. |
| `marketplace/` | Plural and select heavy. Five languages with five different plural systems: `ar` (six categories), `pl` (few/many), `sl` (a dual), `ja` (none), `en`. Compact numbers, offsets, `format_plural_numbers: true`. |
| `bigapp/` | Flutter. 810 messages over nine feature namespaces, `file_pattern: "{namespace}_{locale}"`, `file_per_locale: true`, four locales one of which is a partial rollout under `fill_missing_from_base`. |
| `tms/` | An ARB bundle shaped the way a TMS exports one: flat dotted keys, `@@locale`, `@key` metadata, `intl_*{locale}`, one locale half translated. |
| `bundle_size.py` | Measures what `deferred_locales` and `dynamic_keys` do to a web bundle: 396 messages in four locales, generated each way, compiled with `dart compile js -O4`, bytes printed. The two options are the same fact from opposite ends — what `dart2js` can drop. Deferred loading makes the bundle *bigger* for an entry point that reads one message, because the messages were droppable anyway; a key lookup makes a namespace undroppable, but only once something calls it. |
| `tally.py` | Counts the capability matrix of `docs/competitors.md` and prints the rule it counted by. The figure in that document has been wrong twice; this is so the third time is somebody's disagreement with the rule rather than arithmetic. |
| `probes/` | `./probe.sh` replays twenty-nine deliberate mistakes and prints the diagnostic each one produces — except probe 18, which shows a declaration that used to be dropped and is now honoured. Probe 19 checks a runtime override bundle against the locale's own CLDR categories, and is refused the stamp it asks for; probe 20 stamps a good bundle, moves a nested choice and is refused; probe 21 shows a right-to-left locale with nothing isolating its values, then the same message with `bidi_isolation` on; probe 22 checks a directory of bundles as one release, where two of them claim the same locale and nothing is stamped until the stale one is gone; probe 23 builds a ring of linked messages and a link to a key nothing defines, then shows the same links resolved into literal text; probe 24 links to a placeholder and a plural and then has one locale forget both; probe 25 asks for `deferred_locales` without the layout that allows it, then shows which import becomes a chunk; probe 26 addresses two namespaces by key when one holds a parameterised message and the other does not exist, then generates both enums once they do; probe 27 writes a list and a map whose elements cannot be either, then the same two as `const` accessors, then a list one locale is an element short of; probe 28 writes a list of records whose second element is missing a field, then the interface and class the fixed version generates, then a field that wants a value; probe 29 gives two namespaces a shared interface and takes a member away from one of them, then shows the type both implement once it is back, then a nested namespace with no shared type of its own and the configuration the error prints to fix it. `transcript.txt` is its output. |

## Running everything

```bash
for d in fintech marketplace tms; do (cd evaluation/$d && dart pub get && dart run l10n_plus_generator generate && dart test); done
(cd evaluation/bigapp && flutter pub get && dart run l10n_plus_generator generate && flutter test)
(cd evaluation/probes && ./probe.sh)
```

`fintech`, `marketplace` and `tms` also have a `bin/` entry point that prints
what every message renders to in every locale:

```bash
cd evaluation/marketplace && dart run bin/catalog.dart
```
