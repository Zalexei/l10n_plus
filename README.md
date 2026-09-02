# l10n_plus

Type-safe localization for Flutter and Dart. Translations are data at
development time and a strongly typed Dart API at run time.

> `l10n_plus` is a working name.

```dart
Text(context.l10n.auth.login.title);
Text(context.l10n.auth.login.subtitle(name: user.name));
Text(context.l10n.wallet.transactions(count: transactions.length));
```

Renaming a key, changing an argument, or breaking another locale's translation
fails the build, not the app.

## Packages

| Package | Purpose |
| --- | --- |
| [`l10n_plus`](packages/l10n_plus) | Runtime. Zero dependencies. |
| [`l10n_plus_flutter`](packages/l10n_plus_flutter) | `L10nScope`, `L10nController`, `context.l10n`. |
| [`l10n_plus_generator`](packages/l10n_plus_generator) | JSON + ARB parsers, validator, code generator, CLI. `dev_dependencies` only. |
| [`l10n_plus_builder`](packages/l10n_plus_builder) | Optional `build_runner` adapter over the same generator. |

## Getting started

`pubspec.yaml`:

```yaml
dependencies:
  l10n_plus: ^0.1.0
  l10n_plus_flutter: ^0.1.0

dev_dependencies:
  l10n_plus_generator: ^0.1.0
```

`l10n_plus.yaml` in the project root:

```yaml
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en

class_name: AppLocalizations
locale_enum_name: AppLocale

# Render `#` inside a plural through the locale's NumberFormat (ICU behaviour).
# Off by default: turning it on adds package:intl to any project that writes a
# plural, and changes the output of existing messages.
format_plural_numbers: false

# Where the locale sits in a translation file's path. See "Several files per
# locale" below; the default is one file per locale, named after it.
file_pattern: "{locale}"

# One generated file per locale. Off by default; your import is the same
# either way. See "One generated file per locale" below.
file_per_locale: false

# Let a locale be incomplete: untranslated keys warn and render as the base
# locale. Off by default. See "Untranslated keys" below.
fill_missing_from_base: false

# What to do with a key a locale has and the base locale does not.
# "error" (default) fails the build; "warn" reports it and leaves the key out
# of generation. See "Untranslated keys" below.
extra_keys: error

# Warning codes this project has decided about and does not want reported.
# Errors can never be listed here. See "Turning warnings off" below.
ignore_diagnostics: []

flutter:
  enabled: true
  context_extension: l10n
```

`translations/en.json` — JSON, ARB and YAML are all read, and may be mixed in
one project. By default a JSON or YAML file's base name is its locale tag
(`en.json`, `pt_BR.yaml`); ARB files declare `@@locale` instead. See
[Several files per locale](#several-files-per-locale) to lay them out
differently:

```json
{
  "auth": {
    "login": {
      "title": "Log in",
      "subtitle": "Welcome back, {name}"
    }
  },
  "wallet": {
    "transactions": "{count, plural, =0{No transactions} one{1 transaction} other{{count} transactions}}"
  }
}
```

ARB works too, including bundles exported from `gen_l10n` or a TMS. Dots in a
key become namespaces, and `@key` metadata becomes types and documentation:

```json
{
  "@@locale": "en",
  "auth.login.subtitle": "Welcome back, {name}",
  "@auth.login.subtitle": {
    "description": "Shown under the login title",
    "placeholders": {
      "name": { "type": "String", "example": "Alex" }
    }
  }
}
```

generates

```dart
/// Shown under the login title
///
/// `en`: Welcome back, {name}
///
/// - [name]: Example: `Alex`.
String subtitle({required String name});
```

Then:

```bash
dart run l10n_plus_generator generate
```

The same file as YAML:

```yaml
auth:
  login:
    title: Log in
    subtitle: 'Welcome back, {name}'
```

Quote messages that start with `{` — YAML reads a bare `{` as a flow mapping.
Quote them too when the whole message reads as something else: `true`, `null`,
`~` and anything numeric are not strings in YAML, and the generator says so
rather than letting a translation quietly stop being text. (`yes` and `no` are
fine; YAML 1.2 dropped them as booleans.)

YAML carries no metadata — use ARB when you want declared types, descriptions
or currency settings.

## Plurals and ordinals

```json
{
  "cart.items": "{count, plural, =0{Empty} one{# item} other{# items}}",
  "race.place": "{n, selectordinal, one{#st} two{#nd} few{#rd} other{#th}}",
  "post.likes": "{count, plural, offset:1 =1{You like this} other{You and # others}}"
}
```

Ordinals select on the CLDR **ordinal** table, which differs from the cardinal
one — English gives `1st, 2nd, 3rd, 4th, 11th, 21st`. `offset:` follows ICU:
`=N` branches match the original value, while `#` and the category rules see the
adjusted one.

**Every language CLDR publishes is supported**: 222 for cardinals and 107 for
ordinals, generated from CLDR 48 and checked against CLDR's own `@integer` and
`@decimal` samples. Adding a locale to a project never stops at the rule table.
A category a language does not use is a warning; a language neither table knows
is an error. Nothing falls back to English rules silently.

An explicit `=N` branch counts as covering a category the language defines as
that one value, so the `gen_l10n` shape needs no extra branches:

```json
{"cart.items": "{count, plural, =0{Empty} =1{One item} other{# items}}"}
```

English `one` is "1 and nothing else", so `=1` renders every value it could
select and nothing is reported. Russian `one` also takes 21 and 31, so there
`=1` covers nothing and the missing branch is still a warning.

## Numbers and dates

```json
{
  "wallet.total": "Total: {amount, number}",
  "wallet.statement": "Statement from {from, date, yMMMd}"
}
```

```dart
t.wallet.total(amount: 1234.5)               // en: Total: 1,234.5
                                             // ru: Итого: 1 234,5
t.wallet.statement(from: DateTime(2026, 3, 14))
                                             // en: Statement from Mar 14, 2026
                                             // ru: Выписка от 14 мар. 2026 г.
```

Styles: `decimal`, `integer`, `percent`, `decimalPercentPattern`, `currency`,
`simpleCurrency`, `compact`, `compactLong`, `compactCurrency`,
`compactSimpleCurrency`, `scientific` for numbers; `short`, `medium`, `long`,
`full` or any `DateFormat` skeleton (`yMMMd`, `jm`, `Hms`, …) for dates. `time`
takes only the clock skeletons, because `{t, time, yMMMd}` renders a date and
drops the time. ARB's `"format": "yMMMd"` works too, so a bundle exported from
`gen_l10n` formats correctly without editing any message.

`gen_l10n` spells three of these differently, and both spellings are accepted,
in a message and in ARB alike:

| `gen_l10n` writes | which is |
| --- | --- |
| `decimalPattern` | `decimal` |
| `percentPattern` | `percent` |
| `scientificPattern` | `scientific` |

They are the same style under another name, so a project mixing the two gets
one formatter, and every diagnostic names the canonical spelling.

`decimalPercentPattern` is **not** an alias of `percent`. It is the `intl`
constructor that takes `decimalDigits`, so folding it onto `percent` would
quietly drop the digits an ARB bundle asked for:

```json
"@share": {
  "placeholders": {
    "v": {"type": "double", "format": "decimalPercentPattern",
          "optionalParameters": {"decimalDigits": 2}}
  }
}
```

```dart
t.share(v: 0.4256)   // en: 42.56%   (percent alone gives 43%)
```

`decimalDigits` is the one setting that is not about money: it applies to
`decimalPercentPattern` and to the four currency styles, and to nothing else.

### Currencies

`currency` on its own uses the locale's currency. Append an ISO 4217 code to
pin one, and pick `simpleCurrency` when you want the symbol rather than the
code:

```json
{
  "wallet.local":  "Local: {amount, number, currency}",
  "wallet.price":  "Price: {amount, number, currency:USD}",
  "wallet.symbol": "Price: {amount, number, simpleCurrency:USD}"
}
```

```dart
t.wallet.local(amount: 1234.5)    // ru: Local: 1 234,50 RUB
t.wallet.price(amount: 1234.5)    // en: Price: USD1,234.50
                                  // ru: Price: 1 234,50 USD
t.wallet.symbol(amount: 1234.5)   // en: Price: $1,234.50
                                  // ru: Price: 1 234,50 $
```

`integer` is the decimal pattern with no fraction digits, so `1234.56`
renders as `1,235`.

The amount always keeps the grouping and decimal separator of the rendering
locale; only the currency is pinned. `currency` prints the code because `$` is
ambiguous across USD, CAD and AUD — pick it for finance, `simpleCurrency` for
storefronts.

The code must be three upper case letters. A code on a style that cannot use
one, on a plural or select argument, or disagreeing with the code written in
the message is an error. ICU number skeletons (`::currency/USD`) are not
supported; writing one gets a diagnostic naming the spelling that is.

In ARB, write it the way `gen_l10n` does, so an exported bundle needs no edits:

```json
"@wallet.price": {
  "placeholders": {
    "amount": {
      "type": "double",
      "format": "currency",
      "optionalParameters": {"name": "BTC", "symbol": "₿", "decimalDigits": 8}
    }
  }
}
```

`name`, `symbol` and `decimalDigits` are honoured; `decimalDigits` must be a
whole number from 0 to 20, and `symbol` works with `currency` only, because
deriving the symbol is what `simpleCurrency` is for. `customPattern` is
refused, because a bad pattern only fails once the app is running. These are
ARB only — plain JSON carries no metadata of any kind — so a JSON project
chooses between `currency` and `simpleCurrency`.

Every locale may declare its own `format` and settings, merged over the base
locale's, so a bundle states only what it changes:

```json
// app_ru.arb — roubles by symbol, and without kopecks
"@wallet.price": {
  "placeholders": {
    "amount": {
      "format": "simpleCurrency",
      "optionalParameters": {"decimalDigits": 0}
    }
  }
}
```

What a locale may **not** change is the kind of the argument — a number stays a
number — so the generated signature is the same everywhere. Formatting also
cannot be introduced by one locale alone; declare it in the base too.

Precedence is one rule: the message beats the metadata. What a string writes
decides the style for its own locale, then that locale's declaration, then the
base's. So an override reaches messages written as `{amount}`, which is the
shape ARB bundles have.

Only the *currency* has to agree across locales; two bundles naming different
codes get a warning, while different digits, symbols or styles are the point.

A declared type is kept: `{"type": "double", "format": "currency"}` generates
`required double amount`, the same as writing `{amount, number, currency}`.

`package:intl` is imported **only** by generated files that actually format
something — add it to your `dependencies` when they do; the generator tells you
if you forget.

### Dates need one line at start up

**Any message that formats a date needs its ICU symbols loaded first**, and
`initializeDateFormatting` is asynchronous, so it cannot happen on the way to
the first `DateFormat`. Await the generated initializer before `runApp`:

```dart
Future<void> main() async {
  await initializeAppLocalizationsFormatting();
  runApp(const App());
}
```

Skip it and the first date formatted message throws — while the formatter is
being *built*, not while it formats — and the generated code turns that into an
error naming the call to make:

```
Bad state: Date symbols for "ru" are not loaded.
Call `await initializeAppLocalizationsFormatting()` once during start up,
before reading a date formatted message.
```

Number formats need no initialization, and a project that formats no dates gets
no initializer to call.

### `#` inside a plural

By default `#` interpolates the raw number rather than a formatted one, so that
plurals do not drag `intl` into every project. Two ways to get ICU's behaviour:

* per message — write `{count, number}` instead of `#`;
* per project — set `format_plural_numbers: true`, and every `#` renders
  through the locale's `NumberFormat`:

```dart
t.cart.items(count: 1500)   // off: 1500 items
                            // on:  1,500 items  (ru: 1 500 товаров)
```

The default stays `false`: flipping it changes the output of existing messages
and adds `intl` to projects that had no formatting at all.

## Several files per locale

One file per locale stops scaling somewhere around a few hundred keys.
`file_pattern` says where the locale sits in the path, and everything else in
the name is yours:

```yaml
file_pattern: "{locale}"               # default: en.json
file_pattern: "app_{locale}"           # app_en.arb — the name gen_l10n writes
file_pattern: "{namespace}_{locale}"   # auth_en.json    → t.auth.*
file_pattern: "{locale}/{namespace}"   # en/wallet.json  → t.wallet.*
file_pattern: "*_{locale}"             # auth_en.arb, keys written in full
file_pattern: "**/{locale}"            # wallet/settings/en.json
```

**`{namespace}` puts the file's keys under that name**, so nothing repeats:

```
translations/
  auth_en.json      {"login": {"title": "Log in"}}
  wallet_en.json    {"balance": "Balance: {amount}"}
  auth_ru.json      {"login": {"title": "Войти"}}
  wallet_ru.json    {"balance": "Баланс: {amount}"}
```

```dart
t.auth.login.title
t.wallet.balance(amount: 10)
```

Dots nest: `wallet.settings_en.json` gives `t.wallet.settings`.

**`*` and `**` match and discard**, for files that already write their keys in
full — an ARB bundle exported from a TMS has `auth.login.title` in it, and
prefixing that would give you `auth.auth.login.title`:

```
translations/
  auth_en.arb       {"auth.login.title": "Log in"}
  wallet_en.arb     {"wallet.balance": "Balance: {amount}"}
```

`*` matches one path segment, `**` any number.

Either way the files of one locale are merged, and formats may be mixed inside
a locale. **Groups merge, leaves collide**: two files both adding to `wallet`
is the point, two files both defining `wallet.balance` is an error naming both
of them.

A pattern you configure is a claim about the layout, so a file whose `@@locale`
disagrees with its path is reported, and a file matching nothing is skipped
with the pattern named. The default claims nothing, which is why `app_en.arb`
works unchanged.

## One generated file per locale

By default everything lands in one file, so a one word change to a Russian
string rewrites the file holding every language. For a large app:

```yaml
file_per_locale: true
```

```
lib/generated/
  app_localizations.g.dart       enums, interfaces, part directives
  app_localizations_en.g.dart    English, and the formatters English uses
  app_localizations_ru.g.dart    Russian, and the formatters Russian uses
  app_localizations_flutter.g.dart
```

These are `part` files of one library, so **your import does not change**:

```dart
import 'generated/app_localizations.g.dart';
```

Turning the option on is not a migration. The interfaces, the members and their
order are identical; only the file boundaries move.

With `build_runner`, list the outputs in `build.yaml` — it declares them
statically and cannot know your locales until it reads the translations:

```yaml
targets:
  $default:
    builders:
      l10n_plus_builder:l10n_plus:
        options:
          outputs:
            - "lib/generated/app_localizations.g.dart"
            - "lib/generated/app_localizations_en.g.dart"
            - "lib/generated/app_localizations_flutter.g.dart"
```

If you miss one, the builder names the file it wanted to write.

## Using the generated API

With `flutter.enabled`, the generator writes two libraries: the translations
and the Flutter glue. An application imports both, and needs
`flutter_localizations` for Flutter's own strings in the locales you added:

```dart
import 'package:flutter_localizations/flutter_localizations.dart';

import 'generated/app_localizations.g.dart';
import 'generated/app_localizations_flutter.g.dart';
```

```dart
void main() {
  // No locale argument: the controller opens in the device's language,
  // resolved against the locales you have translations for.
  runApp(DemoApp(controller: createAppLocalizationsController()));
}

class DemoApp extends StatelessWidget {
  const DemoApp({required this.controller, super.key});

  final AppLocalizationsController controller;

  @override
  Widget build(BuildContext context) {
    return L10nScope(
      controller: controller,
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.l10nController.locale.flutterLocale,
          supportedLocales: appLocalizationsSupportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const HomePage(),
        ),
      ),
    );
  }
}
```

`createAppLocalizationsController()` reads
`WidgetsBinding.instance.platformDispatcher.locales` when no `systemLocales`
argument is given, so a Russian phone opens the app in Russian on the very
first frame. Flutter reports `didChangeLocales` only when the locale *changes*,
never at start up, so without that read the first frame would always be the
fallback locale. Reading it initializes the Flutter binding, which means the
factory belongs in `main` or later — where a controller is built anyway.

Two ways to say something else:

```dart
createAppLocalizationsController(locale: AppLocale.en)     // pin a locale
createAppLocalizationsController(systemLocales: const [])  // always fall back
```

Switching locale rebuilds everything that read `context.l10n`:

```dart
context.l10nController.setLocale(AppLocale.ru);
```

A controller built without `locale` keeps following the device, so a language
changed in system settings reaches the app without a restart. `setLocale` stops
that; `useSystemLocale` resumes it.

Translations do not need a `BuildContext`, and none of this needs Flutter:
with `flutter.enabled: false` the generated library is plain Dart and runs on a
server. `L10nLocale` is re-exported by the generated file, so the import above
is the only one.

```dart
final t = AppLocalizations.forLocale(AppLocale.en);
final u = AppLocalizations.of(L10nLocale.parse('pt_BR')); // falls back
```

## build_runner (optional)

The CLI is the primary workflow. If your project already runs `build_runner`:

```yaml
dev_dependencies:
  build_runner: ^2.4.0
  l10n_plus_builder: ^0.1.0
```

`build_runner` only tracks `lib/`, `bin/`, `test/` and friends, so declare the
translation directory and the config file in `build.yaml`:

```yaml
targets:
  $default:
    sources:
      - "lib/**"
      - "translations/**"
      - "l10n_plus.yaml"
      - "pubspec.yaml"
      - "$package$"
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

Both entry points produce byte-identical output, and editing a translation
triggers an incremental rebuild.

## Untranslated keys

A key the base locale has and another locale does not is an error, because a
silently missing string is how `null` reaches a screen. When translations
arrive after the code:

```yaml
fill_missing_from_base: true
```

It becomes a warning, and the message renders exactly as the base locale
renders it — text, plural rules and formatting together:

```dart
/// Untranslated: renders as `en`.
String subtitle({required String name}) => 'Welcome back, $name';
```

Falling back only the text would give you English words under Russian plural
rules — "2 card" — which looks deliberate in a way an untranslated string does
not.

It excuses nothing else: arguments that disagree with the base and a missing
base locale are still errors.

### Keys the base locale no longer has

The opposite case has its own option. A key another locale has and the base
locale does not is an error by default, because the base locale defines the
generated API and a key nothing can reach is usually a typo:

```
translations/ru.json:8:3
removed
error[extra_key]: Key "removed" does not exist in the base locale en.
```

Working through a TMS makes that the wrong default: a key deleted from the base
locale keeps coming back from the translators for days, and nobody can build
until every language has caught up.

```yaml
extra_keys: warn
```

It becomes a warning and the key is left out of generation — the output is
byte for byte what deleting the key by hand would produce. An extra *group* is
reported once, with the number of keys under it, rather than once per key.

This is the only thing it changes. A key the base locale has and this one does
not is still `missing_key`, and arguments that disagree with the base are still
errors.

## Turning warnings off

Some warnings are true and already decided about. At three thousand keys in ten
locales, one plural written without a `few` branch is two thousand identical
`missing_plural_category` lines, and a report that long is not read at all:

```yaml
ignore_diagnostics: [missing_plural_category, unused_plural_category]
```

Only warnings can be listed. A code that always stops the build is refused with
an explanation, and so is a misspelled one — an entry that silences nothing
would otherwise leave you believing a warning is off:

```
warning[invalid_config]: Unknown diagnostic code "missing_plural_categories".
  Nothing reports "missing_plural_categories", so this entry silences nothing.
```

A code that is a warning under one option and an error under another —
`missing_key` with and without `fill_missing_from_base`, `extra_key` with and
without `extra_keys: warn` — may be listed, and only its warning form is
dropped.

The count is always printed, so a project never quietly forgets what it
silenced:

```
No errors. 0 error(s), 3 warning(s). 1842 ignored.
```

## Unused keys

```bash
dart run l10n_plus_generator unused
```

```
translations/en.json:11:5
wallet.deadKey
warning[unused_key]: Nothing refers to "wallet.deadKey".
  No Dart file uses ".deadKey" (3 file(s) searched).
```

Exits non-zero when it finds any, so CI can enforce it.

Names are matched as text, so a key is reported only when its member name
appears nowhere at all — two keys called `title` count as used if either one
is. That is deliberate: the scan will never call a live translation dead. The
generated output, `.dart_tool` and `build` are not searched.

## Development loop

**There is no `l10n_plus_generator watch`.** For automatic regeneration while
you edit translations, use `build_runner`, which has a watcher already:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

That needs `l10n_plus_builder` and the `build.yaml` from
[build_runner](#build_runner-optional) below — `build_runner` does not track a
root level `translations/` directory unless you say so. Both entry points
produce byte-identical output, so switching between them changes nothing in
`lib/generated`.

Without `build_runner`, rerun the CLI:

```bash
dart run l10n_plus_generator generate
```

It rewrites only the files whose contents changed, so a watcher or a running
`flutter run` sees no churn when nothing did.

A CLI `watch` is on the roadmap; until it lands, the above is the answer rather
than a workaround.

## CI

```bash
dart run l10n_plus_generator analyze
```

Exits non-zero on any error and prints file, line, column, translation key, and
what the base locale expected. Add `unused` as a second step when you want dead
translations to fail the build too.

## Benchmarks

```bash
cd example && dart run benchmark/l10n_benchmark.dart
```

Generated calls, measured against the flat `Map<String, String>` the design
rejected. Dart VM, JIT, one machine — read the ratios:

| | generated | flat map |
| --- | --- | --- |
| getter, three namespaces deep | 3.6 ns | 7.5 ns |
| interpolation, one argument | 20.5 ns | 78.5 ns |
| plural, CLDR branch | 21.8 ns | 74.9 ns |

Namespace access allocates nothing — `identical(t.auth, t.auth)` is `true`,
because every namespace object is `const`. Formatting a number costs more than
ten plural branches, which is why formatters are shared and `intl` stays out of
projects that never format.

See [`docs/architecture.md`](docs/architecture.md#benchmarks) for the full
table and the method.

## License

MIT. See [`LICENSE`](LICENSE).

## Development

```bash
flutter pub get          # pub workspace, resolves every package at once
dart format .
dart analyze
dart test packages/l10n_plus packages/l10n_plus_generator packages/l10n_plus_builder
cd example && flutter test
```

Regenerate golden files after an intentional codegen change:

```bash
cd packages/l10n_plus_generator && UPDATE_GOLDENS=1 dart test
```

There is one golden fixture per input format under
`packages/l10n_plus_generator/test/fixtures/`; both must generate the same API
shape. `test/goldens/formats/` holds every formatter the generator can emit and
is derived from the style allowlists themselves, and `test/fixtures/split/`
generates from several files per locale in two formats.

`test/goldens/plurals/` and `test/goldens/ordinals/` are the CLDR rule tables
compiled into Dart, one locale per language CLDR publishes. Regenerate the
tables themselves from a new CLDR release with:

```bash
cd packages/l10n_plus_generator && dart run tool/update_cldr_plural_rules.dart
```

It downloads `plurals.json` and `ordinals.json`, rewrites
`lib/src/plural/cldr_plural_rules.dart` and the sample fixture the tests check
it against, and prints what changed. Run `dart format .` and
`UPDATE_GOLDENS=1 dart test` after it.

`dart analyze` covers the goldens on purpose: they resolve against the real
`package:intl`, so a generated call that does not compile is an analysis error
rather than a surprise in someone's app. Do not exclude them.

The formatter surface golden is also executed, by
`test/goldens_runtime_test.dart`, which imports it and asserts real `intl`
output. Analysis catches calls that do not exist; only running them catches a
setting that is silently dropped.

See [`docs/architecture.md`](docs/architecture.md) for the design and its
trade-offs, and [`docs/roadmap.md`](docs/roadmap.md) for what comes next.
