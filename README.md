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

74 languages have plural rules and the same 74 have ordinal rules; both tables
are checked against ICU's own, so a category a language does not use is a
warning and a language neither table knows is an error naming the ones they
do. Nothing falls back to English rules silently.

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

Styles: `decimal`, `integer`, `percent`, `currency`, `simpleCurrency`,
`compact`, `compactLong`, `scientific` for numbers; `short`, `medium`, `long`, `full` or any `DateFormat`
skeleton (`yMMMd`, `jm`, `Hms`, …) for dates. `time` takes only the clock
skeletons, because `{t, time, yMMMd}` renders a date and drops the time. ARB's
`"format": "yMMMd"` works too, so a bundle exported from `gen_l10n` formats
correctly without editing any message.

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
if you forget. Date formats also need their ICU symbols once at start up:

```dart
Future<void> main() async {
  await initializeAppLocalizationsFormatting();
  runApp(const App());
}
```

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

Switching locale rebuilds everything that read `context.l10n`:

```dart
context.l10nController.setLocale(AppLocale.ru);
```

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

It excuses nothing else: a key the base locale lacks, arguments that disagree
with the base, and a missing base locale are still errors.

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
dart test packages/l10n_plus packages/l10n_plus_generator
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

`dart analyze` covers the goldens on purpose: they resolve against the real
`package:intl`, so a generated call that does not compile is an analysis error
rather than a surprise in someone's app. Do not exclude them.

The formatter surface golden is also executed, by
`test/goldens_runtime_test.dart`, which imports it and asserts real `intl`
output. Analysis catches calls that do not exist; only running them catches a
setting that is silently dropped.

See [`docs/architecture.md`](docs/architecture.md) for the design and its
trade-offs, and [`docs/roadmap.md`](docs/roadmap.md) for what comes next.
