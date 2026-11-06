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

# A top level getter for AppLocalizations.current, for code with no
# BuildContext. Off by default. See "Without a BuildContext" below.
# global_accessor: t

# The Flutter glue: L10nScope, the controller, context.l10n. On by default,
# because most projects are Flutter projects. A Dart project turns it off —
# the glue imports package:flutter, so a Dart project that leaves it on gets
# a missing_flutter_dependency warning rather than a file it cannot compile.
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
dart run l10n_plus_generator generate --watch   # and again on every change
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
one, on a select argument, on a plural count that declares no currency format
to spend it on, or disagreeing with the code written in the message is an
error. ICU number skeletons (`::currency/USD`) are not
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

### Formatting the count, and what it does to the plural

A plural count can also declare its own format, and that wins over both the
default and the flag:

```json
{
  "cards": "{count, plural, one{# card} other{# cards}}",
  "@cards": {
    "placeholders": {
      "count": {"type": "num", "format": "currency"}
    }
  }
}
```

```dart
t.cards(count: 1)   // USD1.00 cards
```

`cards` — not `card`. CLDR selects the plural category from the digits the
reader actually sees, and a currency shows `1` as `USD1.00`: two visible
fraction digits, which English reads as `other`. Drop them and the same value
is singular again:

```json
"count": {"type": "num", "format": "currency",
          "optionalParameters": {"decimalDigits": 0}}
```

```dart
t.cards(count: 1)   // USD1 card
```

This is why the count's format and its plural category cannot be chosen
separately. Tools that pick the category from the value instead render
`USD1.00 card`.

A count that no formatter renders is unaffected: it reads its own value, and a
plural of pure words — `one{Delete the file} other{Delete the files}` — never
consults a formatter at all.

## Linking one message into another

`@:other.key` puts another message's text here:

```json
{
  "brand": {"name": "Acme Cloud", "short": "Acme"},
  "welcome": "Welcome to @:brand.name",
  "tagline": "@:{brand.short} — @:brand.name, simplified"
}
```

```dart
String get welcome => 'Welcome to Acme Cloud';
String get tagline => 'Acme — Acme Cloud, simplified';
```

**Resolved while generating, not at run time.** The product name is written in
place, the message stays a getter, and the generated code is byte for byte what
you would have written by hand — asserted by a test that compares the two.
Nothing is looked up, nothing is allocated, and a chain of links is followed all
the way down. The braces in `@:{brand.short}` are there for a key the sentence
runs into; a trailing full stop ends the sentence rather than the key, so
`@:brand.` links to `brand`.

**A target's parameters become yours.** This is what makes the feature typed
rather than textual:

```json
{
  "greeting": "Hello, {name}",
  "items": "{n, plural, one{# item} other{# items}}",
  "invitation": "@:greeting — you have @:items"
}
```

```dart
String invitation({required String name, required num n});
```

`invitation` writes no placeholder and no plural of its own. It takes both
because the messages it links to do, and the branch is still chosen by the CLDR
conditions compiled into `items` for that locale. Which gives you the one thing
ICU cannot express at all:

```json
{"summary": "@:items in @:folders"}
```

```dart
t.summary(n: 4, d: 1)   // "4 items in 1 folder"
```

**Two plurals in one sentence**, each selecting on its own count. A single ICU
message selects on exactly one argument, so this needs two messages and a way to
put one inside the other.

### What the build refuses

Six new diagnostics, because a link is the one construct in a message whose
correctness is a property of the *project* rather than of the string — plus the
kind conflict that already existed, now reachable through a link:

```
error[unknown_link_target]: No message is keyed "brnd".
  Did you mean "brand"?

error[link_cycle]: These links form a cycle: a -> b -> c -> a.
  Break it: write the shared words out in one of these messages, and let the
  others link to that one.

error[argument_kind_conflict]: Argument "n" is used both as a date and as a plural.
  The plural comes from "n", which this message links to, so both land on one
  parameter here and there is no Dart type that could be both.
```

The other four: a link to a rich message (its spans are structure, not text), a
link *inside* a rich message, a malformed path — which is also what a relative
`@:.sibling` gets, since paths are absolute here — and a link in a runtime
override bundle, which nothing at run time could follow.

A cycle is the one worth dwelling on. In the two packages that have this
feature, a ring of links is not a build error: `slang` guards it only in the
pass that gathers parameters, so two messages linking to each other emit code
that calls itself, and `easy_localization` resolves links at run time with
`// TODO: add recursion detection and a resolve stack.` in its own source.

A message reached only by a link is not reported by [unused keys](#unused-keys):
it is used.

### With runtime overrides on, a link becomes a call

The two features pull in opposite directions, and the configuration already says
which world you are in. With `runtime_overrides: true` a link compiles to a call
on a `const` receiver instead of being written in place:

```dart
return 'Welcome to ${const $BrandEn().name}';
```

So one bundle entry renames the product everywhere it is mentioned:

```dart
AppLocale.en.installOverrides({'brand.name': 'Acme One'});
t.welcome   // "Welcome to Acme One"
t.tagline   // "Acme — Acme One, simplified"
```

The receiver is `const`, so this is one method call and no allocation — the
generated classes have no fields and no pointer to a root, which is what makes
naming one from anywhere free.

Overriding the message that *links* replaces the whole of it, linked parts
included: an override is the words of one branch, and a link is resolved before
there are words. What the link **lends** is still overridable — `summary` never
writes `{n}` and a bundle can place the count anyway.

## Lists and maps

Three onboarding screens are three messages whose *order* is content. Write
them as an array:

```json
{
  "onboarding": {
    "steps": ["Create an account", "Add a card", "You are done"]
  },
  "countries(map)": {"fr": "France", "de": "Germany", "jp": "Japan"}
}
```

```dart
List<String> get steps;                    // t.onboarding.steps
Map<String, String> get countries;         // t.countries
```

```dart
List<String> get steps =>
    const ['Create an account', 'Add a card', 'You are done'];
```

**`const`, so reading one allocates nothing** — the property every other
accessor here has. And the count lives in the translation file: adding a fourth
onboarding step is a translation change, not a Dart change, which is the whole
reason to have lists at all.

A list needs no marker because an array is unambiguous. A map does, and the
suffix is `slang`'s: a group is a map **because its key says so**, never
because of what it holds — otherwise every flat group in every existing
project would silently change its API. The suffix is part of the key, so it is
written in every locale's file, and a Russian bundle spelling `countries` while
English spells `countries(map)` is caught by the rename detection.

Elements are ordinary messages. A link resolves inside one; so does a format.
What they may not do is take arguments:

```
error[invalid_collection_entry]: Element 0 of "steps" takes 1 argument (name),
  and an element takes none.
  Every element of a collection would have to accept every element's arguments,
  which is a parameter list no caller can read — and the accessor could no
  longer be a `const` collection.
  Keep the parameterised message outside the collection and read it by name.
```

The others refused: an element that is itself a list or an object (it would
need a generated type per element), a rich element (it renders spans, not a
string), and `(map)` on a message rather than a group.

**A length difference between locales is the missing key it always was.** The
elements are keyed by index — `steps.0`, `steps.1` — so a list that is three
long in English and two in Russian reports `steps.2 is missing in ru`, at the
right line, with no new machinery. The same for a map key one locale forgot.

With `runtime_overrides` on, each element becomes a member that consults the
store, so a bundle can replace one item of a list:

```dart
AppLocale.en.installOverrides({'onboarding.steps.1': 'Add a payment method'});
```

The override key never carries `(map)`: the suffix tells the generator what to
build, and a bundle names `countries.fr`. `check-overrides` knows every element
and refuses one that does not exist.

### An element can be a record

The onboarding shape, where each step has a title *and* a body:

```json
{
  "onboarding": {
    "pages": [
      {"title": "Create an account", "body": "It takes a minute"},
      {"title": "Add a card", "body": "We never store it"}
    ]
  }
}
```

```dart
abstract interface class $OnboardingPagesItem {
  String get title;
  String get body;
}
List<$OnboardingPagesItem> get pages;
```

```dart
for (final page in t.onboarding.pages) Column(
  children: [Text(page.title), Text(page.body)],
)
```

One interface and one class per locale — not one per element. The values are
known while generating, so the class carries them as fields and the whole list
is one `const`:

```dart
List<$OnboardingPagesItem> get pages => const [
  $OnboardingPagesItemEn(title: 'Create an account', body: 'It takes a minute'),
  $OnboardingPagesItemEn(title: 'Add a card', body: 'We never store it'),
];
```

**And the build checks that every element is the same record.** The first
element declares the fields; an element missing one is an error naming both:

```
error[invalid_collection_entry]: Element 1 of "pages" has no "body", which
  Element 0 of "pages" has.
  Every element is one type, and the first element declares it: "title", "body".
  Add the field to every element, or drop it from this one.
```

That is the check the feature is for. A package that builds a map at run time
can only fail at the field that was missing, on the screen that read it.

A record is **one level deep**: a field is a string, and a field that is itself
an object would need a type of its own and then so would its fields. Fields
take no arguments, for the reason elements do not — interpolate with a link
instead. And `(map)` works the same way: `Map<String, $PlansItem>`.

With `runtime_overrides` on, each field is overridable on its own:

```dart
AppLocale.en.installOverrides({'onboarding.pages.1.body': 'Stored nowhere'});
```

### What this does not do

A list whose elements are *lists* is refused: the index would have to be a
type. And for a **lookup** by a string the server chose, the answer is not a map
but
[`dynamic_keys`](#when-the-server-picks-the-message): a map's `[]` returns
`String?` and a typo is silent, where a key enum's is total and a typo is a
compile error. A map is for the times you need the whole thing — to iterate it,
sort it, or hand it over.

## Namespaces that share a type

Several subtrees often have the same shape. A changelog has one entry per
version, a pricing page one block per plan, an onboarding flow one screen per
step — and the screen that renders them wants to be written once:

```json
{
  "onboarding": {
    "whatsNew": {
      "v2": { "title": "New in 2.0", "rows": ["Add sync"] },
      "v3": { "title": "New in 3.0", "rows": ["New game modes", "And more"] }
    }
  }
}
```

```yaml
interfaces:
  ChangeData: onboarding.whatsNew.*
```

The `.*` means every namespace *under* `onboarding.whatsNew`; without it the
path names that one namespace. A value can also be a list of paths, for
subtrees that are not siblings:

```yaml
interfaces:
  Plan:
    - plans.free
    - plans.pro
```

What comes out is one type, declared once for the project:

```dart
abstract interface class ChangeData {
  /// The `title` of this namespace.
  String get title;

  /// The `rows` of this namespace.
  List<String> get rows;
}
```

The namespaces' own interfaces implement it — `abstract interface class
$OnboardingWhatsNewV2 implements ChangeData` — so the accessor that hands one
out carries the supertype, and the function you wanted is a function:

```dart
Widget changeCard(ChangeData change) => Column(
  children: [
    Text(change.title),
    for (final row in change.rows) Text('• $row'),
  ],
);

changeCard(context.l10n.onboarding.whatsNew.v3);
```

Nothing about it is a run-time lookup: the implementations are the same `const`
classes as before, and the type is the project's rather than one per locale, so
the same function takes `v3` in any language.

### The members have to match, and that is the feature

An element of `whatsNew` that forgets `rows` is a build error:

```
error[invalid_interface]: "onboarding.whatsNew.v3" does not have the members
of "onboarding.whatsNew.v2", which "ChangeData" was read from.
    "rows" is missing
  Every namespace of one interface has the same members with the same
  signatures. The alternative is a nullable member and a `null` on the screen
  that read it, which is the mistake this library exists to find here instead.
```

That is the whole difference from inferring a supertype. `slang`, the one other
package here with the feature, takes the union of what the subtrees have and
makes the difference optional, so `v3.rows` compiles and answers `null`; here
the member set is a fact the build checks. The same applies to signatures: a message taking `{name}` in one
namespace and `{firstName}` in another is reported with both declarations
printed, because they are two different methods wearing one name.

The order of keys inside a namespace does not matter — the members are read by
key — but the generated member order is the first namespace named, so moving a
key in *that* one rewrites the declaration order and nothing else.

### A member that is a namespace

A nested group gets its own entry, and then it is a member like any other:

```yaml
interfaces:
  ChangeData: onboarding.whatsNew.*
  ChangeMeta: onboarding.whatsNew.*.meta
```

A `*` is a path **segment**, not only a suffix: `a.b.*` is every namespace
under `a.b`, and `a.*.b` is the `b` of each. So the nested member of a whole
set is one line, and adding a `v4` stays a change to a translation file.

What comes out keeps both types:

```dart
abstract interface class ChangeData {
  ChangeMeta get meta;        // what a caller holding the supertype reads
}

abstract interface class $OnboardingWhatsNewV2 implements ChangeData {
  $OnboardingWhatsNewV2Meta get meta;   // what the accessor still hands out
}
```

The narrow type overrides the shared one covariantly, so nothing in the
generated API widens: `context.l10n.onboarding.whatsNew.v2.meta` is still the
specific type, which matters because a rich-text helper is an extension on it.

Without the `ChangeMeta` line, `ChangeData` is **refused** — `v2.meta` and
`v3.meta` would be two unrelated types — and the error prints the
configuration to paste:

```
error[invalid_interface]: "onboarding.whatsNew.v2" cannot implement
  "ChangeData", because "meta" is a namespace with no type of its own to share.
  A nested namespace generates a type named after its own path, so
  "onboarding.whatsNew.v2.meta" and "onboarding.whatsNew.v3.meta" are
  different types. Give them one:
    interfaces:
      Meta:
        - onboarding.whatsNew.v2.meta
        - onboarding.whatsNew.v3.meta
```

A nested namespace that is in **two** interfaces is refused as well: a member
has one type, and picking one of the two for you would make the generated
signature depend on the alphabet. An interface over a *single* namespace needs
none of this — there is nothing for the member's type to disagree with.

### A member that is a list of records

A path's **last** segment may name a collection instead of a namespace, and
then the interface is the type of its *elements*:

```yaml
interfaces:
  PlanBlock: plans.*
  Feature: plans.*.features
```

```dart
abstract interface class Feature {
  String get title;
  String get note;
}

abstract interface class PlanBlock {
  List<Feature> get features;              // the shared collection type
}

abstract interface class $PlansFree implements PlanBlock {
  List<$PlansFreeFeaturesItem> get features;   // still the narrow one
}
```

What has to agree is the **field set**, not its order: the generated
constructor takes fields by name, so two collections may list them
differently. A list and a map may share one element type — an element is an
element — and the `(map)` suffix is not part of the path, so the
configuration names `countries` rather than `countries(map)`.

A caller needs no cast in either direction: `List` is covariant in its
element, so `render(List<Feature>)` accepts `plans.free.features` as it
stands. Without the `Feature` line, `PlanBlock` is refused and the error
prints the configuration to paste, exactly as it does for a nested namespace.

A collection of **text** cannot give an element type — every element is a
`String`, so there is nothing to share — and one `interfaces` entry is a
namespace *or* a collection, never both: a namespace is a set of members and a
record is a set of fields, and a type over both would describe neither.

### What this does not do

One thing is still refused: **a namespace addressed by `dynamic_keys`**, whose
`operator []` takes an enum named after the namespace it addresses. Sharing it
would mean one enum over two namespaces' keys, which is a decision about what
the union of two key sets means rather than a missing feature.

The name lives in the configuration rather than in a key suffix, unlike
`(rich)` and `(map)`. Those tell a translator what a value *is*; a Dart type
name tells them nothing, and the translation file is their file. The cost of a
second place is that it can go stale, so a path that matches no namespace is an
error with the nearest one offered.

## When the server picks the message

An error code arrives from an API and some message has to be shown for it. With
a typed API that is a hand-written switch over every code; with a string-keyed
package it is `tr('errors.$code')` and a typo renders as the key. One line asks
for a third thing:

```yaml
dynamic_keys: [errors]
```

```dart
final key = ErrorsKey.tryParse(response.code);   // ErrorsKey?
final text = key == null ? t.errors.unknown : t.errors[key];
```

**What it generates is an enum, not a string lookup.** One value per message of
that namespace, carrying the key as the translation file spells it:

```dart
enum ErrorsKey {
  unknown('unknown'),
  offline('offline'),
  paymentDeclined('payment.declined'),
  paymentExpired('payment.expired');
  ...
  static ErrorsKey? tryParse(String key) { ... }
}
```

So the string stops being a string in exactly one place — `tryParse`, which
returns `null` and nothing else — and everything after it is typed:
`t.errors[key]` is total over the enum, returns a non-nullable `String`, and
has no key to misspell. `ErrorsKey.values` is the contract you can check a
server against, and a `switch` over the enum in your own code is exhaustive, so
a message added to the namespace is a compile error in the code that meant to
handle each one.

Delete a key and `ErrorsKey.paymentExpired` stops existing. That is a compile
error in your app — the thing a string-keyed lookup can never give you.

### Per namespace, and the build says why

Two kinds of message cannot be reached this way, and both are refused rather
than silently skipped:

```
error[unaddressable_dynamic_key]: "declined" cannot be reached by key because
  it takes 1 argument (last4).
  A string naming a message cannot carry its values, and a map of them would be
  the run time lookup this avoids. Move it to a namespace that is not addressed
  by key and call it by name.
```

The other is a rich message, which renders a list of spans rather than a
string. Naming a namespace that does not exist, or that is a message, or that
has nothing under it, is a configuration error with the namespaces listed.

### What it costs — measured

`python3 evaluation/bundle_size.py`, 396 messages in four locales,
`dart compile js -O4`, an entry point that reads one message:

| | first download |
| --- | --- |
| no `dynamic_keys`, read by name | 49,047 |
| one namespace declared, read by name | **49,047** |
| one namespace declared, read through `[]` | 58,298 |
| nine declared, `[]` called on one | **58,298** |
| nine declared, `[]` called on all nine | 141,787 |

Three things in that table. **Declaring a namespace costs nothing** — until
something calls `[]`, `dart2js` drops the lookup and everything it reached.
**Calling it costs that namespace**, 9,251 bytes here for 44 messages in four
locales, because the lookup names every one of them and an unused getter is
only droppable while it is unused. And **declaring nine but calling one costs
one**, which is why the option is per namespace and not per project: the last
row, 141,787 against 49,047, is what addressing a whole project by string
costs, and it is the shape of a flat key-to-message map.

## Rich text

A link or a bold word inside a sentence is not two translations with a widget
between them — the whole sentence has to be one message, because word order is
the translator's business. Mark the key:

```json
{
  "legal": {
    "terms(rich)": "Read the <link>terms of service</link> to continue"
  }
}
```

The `(rich)` suffix is part of the key, so every locale writes it, and the base
file stays pure Dart — spans, no Flutter:

```dart
/// Read the <link>terms of service</link> to continue
List<L10nSpan> get terms => const [
  L10nTextSpan('Read the '),
  L10nTagSpan('link', [L10nTextSpan('terms of service')]),
  L10nTextSpan(' to continue'),
];
```

The Flutter glue adds a wrapper that **requires one builder per tag the message
contains**:

```dart
Text.rich(
  context.l10n.legal.termsRich(
    link: (children) => TextSpan(children: children, recognizer: _tap),
  ),
)
```

Forget the tag and it does not compile. Rename the tag in one locale and the
build fails with `rich_tag_mismatch`, naming both files. The wrapper is
`<member>Rich` because an extension member cannot share a name with the
interface member beside it, and arguments come first:
`greetingRich(name: 'Ada', bold: ...)`.

Tags nest, and a tag may wrap a placeholder with a format on it —
`<b>{amount, number, currency:USD}</b>` works, with no second implementation of
currency formatting behind it.

Three things it deliberately does not do:

* **No attributes.** `<a href="...">` is markup deciding what a tag means; a
  translation is text, and the builder decides.
* **No plurals or selects in a rich message.** The one-builder-per-tag
  guarantee holds only while the tag set is known statically, and inside
  branches it is not. Refused with `rich_unsupported_choice`, which says to
  split the message and choose in Dart.
* **`<` is still a `<`.** `3 < 4` stays text. Only something shaped like a tag
  is a tag, and `<b` with no `>` is `rich_invalid_markup` rather than a guess.

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

### Loading locales on demand

On the web, every locale you support is in the first download. One more line
puts each of them in a chunk of its own:

```yaml
file_per_locale: true
deferred_locales: true
```

The locales stop being `part` files and become libraries behind deferred
imports — all but the **fallback locale**, which stays in the first download so
that something is always renderable. Your import still does not change.

```dart
await AppLocale.ru.load();     // one chunk, fetched now
AppLocale.ru.isLoaded;         // true
await AppLocale.loadAll();     // or pay for everything at once
```

**Nothing throws and nothing is null.** `AppLocalizations.forLocale` stays
synchronous: a locale nobody has loaded reads as the fallback locale, which is
exactly what a locale this app *does not support* has always read as. Loading
is what stops it falling back.

**And an application switching locales needs none of the above.**
`L10nController` starts the load itself and repaints when the chunk lands:

```dart
controller.setLocale(AppLocale.ru);        // switches now, repaints on arrival
await controller.setLocaleAsync(AppLocale.ru);  // or skip the fallback frame
```

One thing to know before you write a widget test for that switch: a deferred
load **does not complete under a widget test's fake clock**, and awaiting its
future afterwards does not rescue it — `loadLibrary` hands out one future per
library and that one is stuck. A side effect worth knowing too: no two tests in
one file can load the same locale, because a half-loaded one cannot be retried.
Drive the switch inside `runAsync`:

```dart
await tester.runAsync(() async {
  controller.setLocale(AppLocale.ru);
  while (!AppLocale.ru.isLoaded) await Future<void>.delayed(Duration.zero);
});
await tester.pump();
```

### What it actually saves — measured, both ways

Run it yourself: `python3 evaluation/bundle_size.py` builds 396 messages in
four locales, compiles each way with `dart compile js -O4` and prints the
bytes.

| 396 messages × 4 locales | first download | everything served |
| --- | --- | --- |
| one library | 189,632 | 189,632 |
| `deferred_locales` | **113,148** | 208,206 |

A 40% smaller first download, and 10% more bytes if the user eventually loads
every language. That is the trade, and it is the expected one.

**The unexpected one is the row below**, and it is why this option is off by
default. With the same four locales and an entry point that reads *one*
message:

| 396 messages × 4 locales, one read | first download |
| --- | --- |
| one library | 49,047 |
| `deferred_locales` | 69,995 |

Deferred loading made the bundle **43% bigger**. Two things cause it. `dart2js`
already tree-shakes the messages an app never reads — a generated message is a
getter on a `const` class, and an unused getter is dead code, which is not true
of a package whose translations are a map built at run time. And the deferred
loader itself is a fixed cost: those two numbers differ by 20,948 bytes while
the chunks hold 597 bytes each, so that is the chunk-loading machinery and
nothing else.

So the option pays for itself when an application renders a lot of its
messages in a lot of languages, and costs you about 21 KB when it does not. At
36 messages per locale it is already the wrong trade — 64,011 bytes one library
against 73,118 deferred, which is the second size the script prints. Measure
your own app before turning it on.

For context: a release Flutter web build is a megabyte and a half of engine and
framework before any of this, so 76 KB is real but it is not the number that
decides your load time.

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

### Without a `BuildContext`

A BLoC, a service or a notification wants the language the screen is in, and
has no context to read it from:

```dart
AppLocalizations.current.errors.network
```

`current` reads `AppLocalizations.currentLocale`. The controller made by
`createAppLocalizationsController` keeps that in step with what it shows — at
start up, on `setLocale`, on a language changed in system settings. Without a
controller — a server, a test, a background isolate — set it yourself; until
then it is the fallback locale, never `null`.

```dart
AppLocalizations.currentLocale = AppLocale.ru;
```

One line names a shorter getter, if the project wants one:

```yaml
global_accessor: t   # AppLocalizations get t => AppLocalizations.current;
```

Off by default, because a one letter name at the top of a library is a
decision about your namespace (`final t = ...` is a common local, and this
README writes it).

**It is a snapshot, not a subscription.** `context.l10n` registers the widget
for a rebuild; `current` does not, and a string read from it keeps the
language it was read in:

```dart
emit(ErrorState(message: t.errors.network));   // "Ошибка сети"
// the user switches to English: the screen rebuilds, the state does not —
// it still says "Ошибка сети"
```

Store what the text *is*, and translate where it is shown:

```dart
emit(ErrorState(message: (t) => t.errors.network));
// in build:
Text(state.message(context.l10n))
```

or, for a message the server chose, the key enum
[`dynamic_keys`](#when-the-server-picks-the-message) generates. `current` is
the right tool for text used once, at the moment it is read: a push
notification, a log line, an email body, a snackbar shown now.

Two more things it is not:

* **Not shared between isolates.** A static is per isolate, so inside
  `compute` or a background worker `current` is the fallback locale until that
  isolate sets `currentLocale` itself.
* **Not per controller.** With two controllers alive — tests, a second
  window — the one that changed last wins. Tests that read `current` reset it
  in `tearDown`:
  `AppLocalizations.currentLocale = AppLocalizations.fallbackLocale`.

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

## Renaming a key

Renaming a key in the base locale leaves every other locale with the old name.
That is one edit, so it is one finding rather than a `missing_key` and an
`extra_key` per language:

```
translations/auth_de.json:3:5
auth.login.title
error[renamed_key]: Key "title" looks renamed to "headline" in en.
  Base locale en: auth.login.headline (auth_en.json:3)
  de locale: auth.login.title (auth_de.json:3)
  They are the only difference in "auth.login", so rename it here too.
```

Only when a namespace has exactly one missing key and exactly one extra one:
two of each could be two renames or four unrelated edits, and those are
reported separately rather than guessed at.

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

## Right-to-left locales

A locale knows which way it reads, decided by its script and never by its
region:

```dart
L10nLocale.parse('ar').isRightToLeft;       // true
L10nLocale.parse('ar-EG').isRightToLeft;    // true
L10nLocale.parse('az-Latn').isRightToLeft;  // false
L10nLocale.parse('az-Arab').isRightToLeft;  // true
```

The lists behind it are CLDR 46's own: a script is right to left when
`scriptMetadata.txt` marks it so, a language when `likelySubtags.xml` maps it
to such a script. An explicit script subtag always wins, so romanized Urdu
(`ur-Latn`) is left to right and `pa-Arab` is not.

In Flutter it is a `TextDirection`, on the locale and on the controller, so
nothing below the scope has to know about locales at all:

```dart
Directionality(
  textDirection: L10nScope.controllerOf(context).textDirection,
  child: child,
)
```

The controller derives it from the active locale, so it notifies the same
listeners the locale does: switching to `ar` flips the layout.

### Filling an untranslated right-to-left locale

`fill_missing_from_base` plus a locale that reads the other way round is the
one combination worth a warning of its own:

```
warning[fill_direction_mismatch]: ar is right-to-left, but 3 messages fall
back to left-to-right en text.
```

Those keys are already reported as `missing_key`. What this adds is why they
are worse than missing: filled text is a complete, grammatical sentence, so the
screen looks finished while reading backwards, with punctuation, brackets and
embedded numbers on the wrong side. A reviewer who does not read the base
language cannot tell it from a translated screen, so it ships. Set
`fill_missing_from_base: false` to make those keys an error again, leave the
locale out of the build until the translations land, or add
`fill_direction_mismatch` to `ignore_diagnostics` once a mixed-direction
rollout is the decision rather than the accident.

### Isolating interpolated values

A value is whatever somebody typed, so its direction is not the sentence's, and
the bidi algorithm will reorder the two against each other. Laid out in a Hebrew
line, a value ending in a full stop gets the stop on the wrong side of it, a
value beginning with digits comes out back to front, and `-5%` renders as `5%-`.
Every string comparison still passes, which is why nobody finds it until a
screenshot arrives:

```
a Hebrew sentence with the value "-5%" in the middle of it
  without the isolates   the minus is laid out after the percent:  5%-
  with them              the value is laid out as it was written:  -5%
```

(Shown without the Hebrew words around it: a line of visual order is itself
reordered by whatever renders this page.)

Turn it on:

```yaml
bidi_isolation: true
```

Every placeholder that sits in text is then emitted between U+2068 FIRST STRONG
ISOLATE and U+2069 POP DIRECTIONAL ISOLATE:

```dart
String greeting({required String name}) => 'Hi \u{2068}$name\u{2069}, welcome';
```

Every locale, not only the right-to-left ones: an embedded Hebrew name in an
English sentence is the same problem seen from the other side.

Two characters in a string literal, so nothing is computed at run time and
nothing is measured twice: `FSI` takes the direction of the value's own first
strong character, which is the one thing a generator cannot know.

Off by default, and a project with a right-to-left locale is told once:

```
warning[bidi_isolation_off]: Values are interpolated into he, which is written
right to left, and nothing isolates them.
```

It is off by default because the isolates are invisible, so a test comparing a
rendered message against a literal has to carry them too. Add
`bidi_isolation_off` to `ignore_diagnostics` if that trade is not yours to make.

A message that is *nothing but* a placeholder is left alone — there is no text
in that string to be reordered against, and the widget's own direction decides
the line. In a rich message the same placeholder alone in one span *is* isolated,
because the rest of the sentence is in the sibling spans. A nested plural's
rendering is never isolated: it is this locale's own words, and whatever value
sits inside it was isolated where it was interpolated.

The claim here is about layout, not about strings, so it is tested as layout:
`packages/l10n_plus_flutter/test/bidi_isolation_test.dart` lays each case out
with a `TextPainter` and reads the character positions back. It also records the
two cases the bidi algorithm already gets right, where the isolates change
nothing.

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

## Watching

```bash
dart run l10n_plus_generator generate --watch
```

Regenerates whenever a translation file, `l10n_plus.yaml` or `pubspec.yaml`
changes, printing what it wrote and what it left alone. The configuration is
re-read every time, so changing it takes effect without restarting, and an
error does not stop the watch — fix the file and it regenerates. Nothing else
in the project is watched, so saving a Dart file costs nothing.

Only `generate` takes it: `analyze` and `unused` answer a question once.

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

A message counts as used only when **every** name on its path appears
somewhere: reaching `t.wallet.limits.title` means writing `.wallet`, `.limits`
and `.title`, in one expression or spread across locals and helpers. So a
namespace nobody enters takes everything under it with it, and those collapse
into one finding:

```
translations/wallet_en.json:41:5
wallet.limits
warning[unused_key]: Nothing refers to anything under "wallet.limits".
  No Dart file uses ".limits" (12 file(s) searched).
  Nothing reaches into "limits", so the 6 message(s) under it are unreachable:
    wallet.limits.title
    …
```

Names are still matched as text, so two keys under one namespace that both
appear cannot be told apart. That is deliberate: the scan will never call a
live translation dead. The generated output, `.dart_tool` and `build` are not
searched.

## Handing strings to a translator

Strictness is a wall until the strings can leave the repository and come back.

```bash
dart run l10n_plus_generator export                 # l10n_plus_export.csv
dart run l10n_plus_generator export --format=arb    # one .arb per locale
```

CSV is one row per message — key, base text, a column per locale — for a
translator with a spreadsheet. ARB is a bundle per locale, with `@@locale` and
`@key` metadata, for a TMS.

Back in:

```bash
dart run l10n_plus_generator import --from=hand_off.csv           # dry run
dart run l10n_plus_generator import --from=hand_off.csv --write
```

**The dry run is the default**, and prints what each locale would gain or
change. With `--write`, new text is spliced in at each message's own position,
so key order, blank lines, YAML comments, indentation and line endings survive —
the diff is the translations and nothing else.

Both commands run **before** cross-locale validation, on purpose: under the
default configuration an incomplete locale is an error, and that locale is
exactly the one somebody is exporting for. Parse errors still stop them.

What it will not do:

* **Create nothing.** A locale with no file is `unknown_interchange_locale`, a
  key with nowhere to go is `unplaceable_key`. Inventing a file name and layout
  is the tool deciding how your repository is arranged.
* **Delete nothing, reorder nothing.** A key dropped from the hand-off file
  stays as it was.
* **An empty cell means "nothing supplied"**, never "set this to empty", so a
  blank column cannot wipe a translation.
* **Descriptions are read-only**, and the exported ARB carries only what a
  translator needs — it is not a replacement for your own bundle.

A dry run with pending changes still exits 0. It reports; `analyze` is what
fails a build.

## Changing text without a release

A typo, a legal reword, a price that is suddenly wrong — copy changes that
should not wait for review. Turn the option on:

```yaml
runtime_overrides: true
```

Fetch a bundle however your application already fetches things, and install it:

```dart
final json = await myApi.translations('ru');     // yours: HTTP, cache, auth
AppLocale.ru.installOverrides(json);
```

Every screen reading translations repaints. `setLocale` is still synchronous,
and there is no `http` anywhere in these packages — the fetching, the caching
and the credentials stay yours.

A bundle is a flat map of dotted keys. A message with one form takes a string; a
message the generated code branches on takes one string per branch:

```json
{
  "@@locale": "ru",
  "auth.login.title": "Войти",
  "wallet.transactions": {
    "one": "# операция",
    "few": "# операции",
    "many": "# операций",
    "other": "# операции"
  }
}
```

`{name}` is an argument, `#` is the plural count, and both are substituted with
the value the compiled message would have printed — currency, digits and all.
**What an override cannot do is change the API**: no new key, no new or removed
placeholder, no new branch. Those are a release.

That is also why the branch names are plural *categories* rather than numbers:
the category is still chosen by the CLDR rules compiled into your app, so the
override supplies the words for a branch and never the rule that picks it. A
nested choice is numbered — `"0/one"` for its branches, `{#0}` in the text
around it.

### Check the bundle before it ships

```bash
dart run l10n_plus_generator check-overrides --from=overrides_ru.json --stamp
```

```
error[unknown_override_branch]: "two" is not a branch of "items" in ru.
  CLDR 48 gives "ru" the categories few, many, one, other here, so nothing in
  it can select a "two" branch.
```

It also catches a key the project does not define, a placeholder the message
does not take, `#` in a message with no count, and ICU inside an override —
twelve errors in all, each one a mistake a bundle can be fixed for before
anybody sees it. Run it in the job that publishes the bundle, not only locally:
at run time nothing throws, and an unknown `{token}` is left standing in the
string, because a wrong override must not crash an application that is already
in somebody's hands.

A rich message cannot be overridden: its spans are structure, not text.

### The bundle says which build it was checked against

Every answer above is an answer about your project as it stands, and a bundle
outlives a build. The branches of a nested choice are addressed by position, so
a release that puts another plural ahead of one renumbers it — and every name in
last week's bundle still exists, so the check still passes and the text of one
choice has quietly become the text of another:

```
compiled:  You have 1 wallet with 1 card linked
installed: You have 1 saved card with 1 card linked
```

So `--stamp` writes into the checked bundle the surface it was checked against:

```json
{"@@fingerprint": "59d2616f9e765ee8", "@@locale": "ru", ...}
```

`installOverrides` carries this build's own, as a constant in the generated
file, and refuses any other — `L10nOverrideMismatch`, nothing installed, the app
still on the text it compiled, which is the right text for the build that is
running. Catch it where you fetch:

```dart
try {
  AppLocale.ru.installOverrides(json);
} on L10nOverrideMismatch catch (error) {
  log(error);                      // ship a bundle re-stamped for this build
}
```

The fingerprint covers the keys, the branches, the placeholders each branch
substitutes and the numbering of the nested choices — never the text, so the
rewording release an override exists to avoid waiting for does not invalidate
anybody's bundle. It is one value per locale, so a release that *adds* a message
does: re-run the check with `--stamp`, which is the release that had to re-check
its bundles anyway. It identifies, it does not authenticate — anybody who can
replace the bundle can replace the fingerprint in it, and the download is TLS's
business.

### A release is a directory, not twelve invocations

Twelve languages is twelve bundles, and `--from` takes the directory they are
in:

```bash
dart run l10n_plus_generator check-overrides --from=overrides/ --stamp
```

```
overrides/ar.json  ar  2 of 20 message(s), 3 text(s)  04e15327e0a5ff8b  stamped
overrides/en.json  en  3 of 20 message(s), 4 text(s)  176950849f196557  stamped
overrides/ru.json  ru  4 of 20 message(s), 8 text(s)  8b052faf63c2d73f  stamped
3 bundle(s) in "overrides/", 3 of 4 locale(s). No errors.
No bundle for: de. Those locales keep the text they compiled.
```

Every `.json` in the directory, each for the locale it names, each signed with
its own surface. It is not a loop for convenience: three of those answers do
not exist a file at a time, and a rollout checked a file at a time can pass
twelve times and still be wrong as a set.

**Which locales have no bundle.** The last line. Not overriding a locale is
normal and correct — it keeps the text it compiled — and it is also what a
rollout forgets. Nothing about `overrides/de.json` not existing is visible when
you are naming files one by one.

**Two bundles for one locale.** An old bundle left beside the new one: both are
valid, both pass every per-file check, and which of them your application
installs is decided by whatever serves them. A bundle's locale comes from
`@@locale` or from its file name, so the clash can be between two declarations,
two names, or one of each.

```
error[duplicate_override_locale]: Two bundles here are for "en":
  "overrides/en.json" and "overrides/old_en.json".
  A locale has one overridable surface, and the application installs one
  bundle for it. Which of these two takes effect is decided by whatever serves
  them, so both passing this check says nothing about which text ships.
```

**The release is signed whole or not at all.** `--stamp` validates every bundle
before it writes any. A release in which some bundles carry a fingerprint and
some do not is one where nothing on disk says which of them was checked, so one
bad branch in Russian leaves all twelve unstamped — and says so.

With the option off — the default — none of this is generated and your output is
byte for byte what it was. With it on, a message read costs 1.8 ns more while
nothing is installed.

## Development loop

Editing translations while the app runs wants a watcher. There are two, they
produce the same bytes, and neither is the workaround:

```bash
dart run l10n_plus_generator generate --watch
```

```bash
dart run build_runner watch --delete-conflicting-outputs
```

The CLI watcher needs nothing beyond the generator and is described under
[Watching](#watching). `build_runner` needs `l10n_plus_builder` and the
`build.yaml` from [build_runner](#build_runner-optional), because it does not
track a root level `translations/` directory unless you say so.

Either way, generation rewrites only the files whose contents changed, so a
running `flutter run` sees no churn when nothing did. A one-off regeneration
is the same command without `--watch`:

```bash
dart run l10n_plus_generator generate
```

## CI

```bash
dart run l10n_plus_generator analyze
```

Exits non-zero on any error — in a translation *or* in `l10n_plus.yaml` — and
prints file, line, column, translation key, and what the base locale expected.
With `fill_missing_from_base` it also says how far each locale has got:

```
No errors. 0 error(s), 18 warning(s).

Translated:
  de  270/270
  en  270/270
  fr  1/270  (0%, 269 untranslated)
  ru  270/270
```

Add `unused` as a second step when you want dead translations to fail the
build too.

## Benchmarks

```bash
cd example && dart run benchmark/l10n_benchmark.dart
```

Generated calls, measured against the flat `Map<String, String>` the design
rejected. Dart VM, JIT, one machine — read the ratios:

| | generated | flat map |
| --- | --- | --- |
| getter, three namespaces deep | 3.8 ns | 8.1 ns |
| interpolation, one argument | 22.0 ns | 83.1 ns |
| plural, CLDR branch | 22.8 ns | 79.4 ns |

Namespace access allocates nothing — `identical(t.auth, t.auth)` is `true`,
because every namespace object is `const`, and a test reads the generated
source to check that every accessor in it is.

Through Flutter, `context.l10n` and three getters cost about 50 ns against
6 ns for the same call without a `BuildContext`; the difference is Flutter's
inherited widget lookup. Switching locale rebuilds exactly the widgets that
read it. Formatting a number costs more than ten plural branches, which is why
formatters are shared and `intl` stays out of projects that never format.

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
