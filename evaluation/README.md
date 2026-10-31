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
| `probes/` | `./probe.sh` replays eighteen deliberate mistakes and prints the diagnostic each one produces — except the last, which shows a declaration that used to be dropped and is now honoured. `transcript.txt` is its output. |

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
