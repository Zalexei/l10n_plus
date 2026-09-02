# l10n_plus architecture

Working name. Nothing in the code depends on it.

## Guiding principle

> Translations are data at development time and a strongly typed Dart API at
> run time.

Everything that can be decided while generating code is decided there: key
lookup, ICU parsing, plural rule selection, argument typing. What reaches the
application is ordinary Dart — string literals, `if` chains and `switch`
expressions behind an interface.

## Packages

Three packages, not four.

| Package | Role | Ships in an app? |
| --- | --- | --- |
| `l10n_plus` | Runtime: locale value type, fallback resolution, plural operands, the interfaces generated code implements. | yes, `dependencies` |
| `l10n_plus_flutter` | Flutter edge: `L10nController`, `L10nScope`, `Locale` interop. | yes, `dependencies` |
| `l10n_plus_generator` | Source parsers, ICU parser, validation, code generation, and the CLI in `bin/`. | no, `dev_dependencies` |
| `l10n_plus_builder` | `build_runner` adapter over the same generator API. | no, `dev_dependencies`, optional |

```
        l10n_plus_generator   (dev only; emits source text, imports no runtime API for codegen)
                 |  generates
                 v
        app_localizations.g.dart ---------> l10n_plus
        app_localizations_flutter.g.dart -> l10n_plus_flutter -> flutter
```

### Why `l10n_plus_builder` *is* a separate package

The argument that kept the CLI inside the generator produces the opposite answer
here. The builder has a real dependency the CLI must never carry — `build` — and
projects that use the CLI should not resolve it. It is also genuinely optional:
the CLI remains the primary workflow.

The adapter is thin because the pipeline was already IO-free in spirit:
`generate(inputs)` takes translation files that have already been read and
returns files to write, while `run()` is the `dart:io` convenience wrapper the
CLI uses. The builder reads each translation file through `BuildStep`, which is
what makes `build_runner` treat it as a tracked input and rebuild on change —
verified end to end, including an incremental rebuild after editing one string,
and both entry points produce byte-identical output.

The one wart is `build_runner`'s default source set: it tracks `lib/`, `bin/`,
`test/` and friends, so a root level `translations/` directory and
`l10n_plus.yaml` must be declared in the consuming package's `build.yaml`. That
is a `build_runner` rule, not something the adapter can paper over, so the
example ships the exact `build.yaml` needed.

### Why not a separate `l10n_plus_cli`

The CLI is an entry point, not a reusable library. It already depends only on
`L10nPlusGenerator`, so the boundary that matters — *generation engine knows
nothing about the CLI* — is a module boundary and is enforced by imports. A
fourth package would add a release surface and a version constraint for zero
architectural gain. A `build_runner` adapter, when it arrives, will be a real
package because it has a real dependency (`build`) that the CLI must not carry.

### Why `l10n_plus_flutter` is separate

Generated translations are usable from pure Dart: servers, CLIs, unit tests.
Folding the Flutter widgets into the runtime would make `flutter` a transitive
dependency of every consumer. It also keeps rule 3 mechanical rather than
aspirational: the runtime package cannot import Flutter because it does not
depend on it.

### Dependency policy

`l10n_plus` has **zero** dependencies. `l10n_plus_flutter` depends on `flutter`
and `l10n_plus`. The generator carries `source_span`, `yaml`, `path`, `args`,
`dart_style` and `l10n_plus` — all dev-time only.

The generator depends on the runtime purely to reuse `L10nLocale`; duplicating
locale canonicalization in two packages would be a correctness hazard, and the
direction generator → runtime is acyclic.

## Pipeline

```
translations/*.json, *.arb, *.yaml
      │  SpanJsonParser          span-aware JSON, because dart:convert drops positions
      ▼
  JsonSourceParser               → TranslationDocument (groups, leaves, spans, metadata)
  ArbSourceParser                  the last stage that knows the source format
      │
      ▼
  IcuMessageParser               → MessageBody AST per leaf
      ▼
  MessageSignature.infer         → argument names and kinds, from the base locale
      ▼
  CrossLocaleValidator           → every other locale checked against the base
      ▼
  ModelBuilder                   → Dart identifiers, namespaces, select enums
      ▼
  DartEmitter / FlutterEmitter   → source text
      ▼
  dart_style                     → formatted, byte stable output
```

Stage responsibilities:

* **Source parser** — the only format-aware stage. Adding a format means adding
  a `TranslationSourceParser` and nothing else; ARB was added that way, and a
  golden fixture generates the same API from `.arb` as from nested `.json`.
* **ICU parser** — turns a message string into an AST. No regex substitution
  anywhere in the codebase.
* **Signature inference** — decides the Dart parameter list from the base
  locale message only.
* **Validator** — the base locale is the API contract. Anything another locale
  does differently would produce code that cannot exist, so those are errors.
* **Model builder** — the only place where translation keys become Dart
  identifiers, and where collisions are detected.
* **Emitters** — no decisions left, only rendering.

The pipeline performs **no writes**. `GenerationResult` carries the files, and
the caller (today the CLI, tomorrow a `build_runner` adapter) decides what to do
with them.

## AST

Two layers, deliberately.

**Structure layer** (`TranslationGroup`, `TranslationLeaf`) is source-format
independent and carries spans plus a `MessageMetadata` — the description and
placeholder declarations a format may provide. JSON leaves it empty; ARB fills
it from `@key`.

**Message layer** is the ICU AST: `LiteralNode`, `ArgumentNode`,
`NumberSignNode`, `PluralNode`, `SelectNode`, composed into `MessageBody`.
`PluralCase` is a sealed `ExactPluralCase | CategoryPluralCase`, which is what
lets `=0` be emitted before the CLDR conditions without a special case in the
emitter. `selectordinal` is rejected with a dedicated diagnostic rather than
silently mishandled; adding it later means one more node type and one more rule
table.

## Decisions and trade-offs

### Generated strings vs runtime maps

**Chosen: generated strings.** A runtime map keyed by string is smaller to
generate but reintroduces exactly what this library exists to remove — a lookup
that can miss, and an argument list that is not typed. The cost is generated
file size, which is bounded by the number of messages times the number of
locales and is plain Dart the compiler can tree-shake.

### `num` vs `int` for plural arguments

**Chosen: `num`.** CLDR plural selection reads the *visible fraction digits* of
the number: `1` is `one` in English but `1.0` is `other`. Typing the parameter
as `int` makes correct handling of "2.5 stars" impossible, and `count: 5` still
compiles. `PluralOperands` computes `n, i, v, w, f, t` from the `num`.

### Plural rules: runtime table vs generated conditions

**Chosen: generated conditions.** The generator knows the locale it is emitting,
so it inlines that locale's rule as Dart:

```dart
final $operands = PluralOperands(count);
if ($operands.v == 0 && $operands.i % 10 == 1 && $operands.i % 100 != 11) {
  return '$count транзакция';
}
```

No rule table ships to the app, and there is no per-call rule dispatch. The
generator holds a **curated** CLDR table of 74 languages; an unknown language
produces `unknown_plural_language` rather than silently falling back to
English rules, which is the classic way localization libraries ship wrong
plurals.

Curated means written by hand, which means wrong sooner or later, so both
tables are checked against a second implementation of the same data:

* **cardinals** against `package:intl`, which carries its own copy generated
  from ICU data. `test/plural_matrix_test.dart` derives one message per
  language from the table itself, and
  `test/plural_matrix_runtime_test.dart` executes the generated code and
  compares every branch against `Intl.pluralLogic`. It has one known defect
  of its own — `intl` computes the operand `i` as `n.round()` where CLDR says
  the integer digits — so values ending in `.5` are asserted against CLDR's
  published samples instead;
* **ordinals** against ICU directly, because `intl` has no ordinal table.
  `Intl.PluralRules(locale, {type: 'ordinal'})` in Node is that table;
  `tool/ordinal_oracle.sh` dumps its answers for 1214 values per language
  into `test/data/cldr_ordinals.json`, and
  `test/ordinal_matrix_runtime_test.dart` compares against the dump. The
  answers are vendored rather than queried, so the suite needs nothing but
  Dart; the script exists so the file can be regenerated and argued with.

### Select arguments: enum per message argument

**Chosen: one enum per `(message, argument)`, named from the key path.**
`profile.greeting` + `gender` → `ProfileGreetingGender`. Deduplicating enums by
value set was rejected: it would couple unrelated messages, so adding a branch
to one message would silently change another's API. Message paths are unique, so
names cannot collide; collisions with the generated class or locale enum are
still checked and reported.

All *internal* generated classes are prefixed with `$` (`$Auth`, `$AuthLoginEn`),
which keeps the user-facing enum namespace clean and makes collisions between
namespaces and enums structurally impossible.

### Object graph: `const`, not lazy fields

Namespace accessors return `const` instances:

```dart
@override
$AuthLogin get login => const $AuthLoginEn();
```

Every namespace object is canonicalized at compile time, so `context.l10n.auth.login.title`
allocates nothing and holds no back-reference to its root. A `late final` field
per namespace would allocate once per locale; `const` allocates zero times. The
cost is that messages cannot reference other messages (linked translations); when
that feature arrives it will need a root reference, and that is a deliberate
future trade rather than an upfront one.

### Nested plural/select inside text

A message whose body *is* a plural is emitted as statements. A plural nested
inside text (`"You have {count, plural, ...} linked"`) is emitted as a private
helper method and interpolated:

```dart
String summary({required num count}) => 'You have ${_summary$0(count: count)} linked';
```

This keeps every case a plain method call — no closures, no allocation, and the
generated code stays readable at arbitrary nesting depth.

### Number and date formatting: `intl` in the generated file, not the runtime

The obvious place for `intl` is the runtime package. It is the wrong one: every
app would pay for it, including the majority that never format a number.

Instead the **generated file** imports `package:intl` — and only when at least
one message actually formats something. `l10n_plus` keeps its zero dependencies,
and a project with no `{n, number}` or `{d, date}` anywhere never sees intl in
its graph. A test asserts both halves of that.

Formatters are emitted as lazily initialized top level finals, one per locale
and style:

```dart
final NumberFormat _ruNumberDecimalPattern = NumberFormat.decimalPattern('ru');
...
String total({required num amount}) => 'Итого: ${_ruNumberDecimalPattern.format(amount)}';
```

Constructing a `NumberFormat` parses a pattern, so doing it per call would
undo the point of generating code. A top level final is built once per isolate
on first use and then is a plain field read.

Because the generator knows which locales exist, the app must add `intl` to its
own `dependencies`. Forgetting that would surface as an unresolved import in
generated code, which reads like a generator bug — so the generator reads the
project's `pubspec.yaml` and reports `missing_intl_dependency` itself.

**Date symbols must be loaded first.** Number symbols are compiled into `intl`,
but `DateFormat` for a non-default locale needs `initializeDateFormatting`. When
any date format is generated, the generator emits

```dart
Future<void> initializeAppLocalizationsFormatting() async { ... }
```

covering exactly the project's locales, and the demo awaits it before `runApp`.

### Ordinals use a second rule table

`{n, selectordinal, ...}` selects on the CLDR **ordinal** table, which is a
different table from the cardinal one and not derivable from it: English is
`one/two/few/other` for ordinals (1st, 2nd, 3rd, 4th) but only `one/other`
for cardinals, while Slovenian is the reverse — four cardinal categories and
one ordinal. Both are curated, and a language missing from the ordinal table
produces `unknown_ordinal_language` rather than silently borrowing English
behaviour.

The two tables cover the same 74 languages, and a test says so, because a
language that can count things but cannot number them is a gap rather than a
decision.

Some ordinal rules are written over `n` and some over `i`, exactly as CLDR
writes them, and the difference shows on input that should not exist: English
`1.5` is `other` because its rule reads `n % 10 = 1`, while Azerbaijani `1.5`
is `one` because its rule reads `i % 10 = 1`. There is no 1.5th of anything;
matching ICU is cheaper than explaining a difference.

A message that is a cardinal plural in one locale and an ordinal in another is
an error: the two select on different rules and mean different things.

### `offset:` adjusts the value, but not the `=N` branches

ICU says explicit `=N` branches match the **original** value while the category
rules and `#` see the offset one. The emitter follows that exactly:

```dart
String likes({required num count}) {
  if (count == 0) return 'Nobody likes this';
  if (count == 1) return 'You like this';
  final $countOffset = count - 1;
  final $operands = PluralOperands($countOffset);
  if ($operands.i == 1 && $operands.v == 0) {
    return 'You and ${$countOffset} other like this';
  }
  return 'You and ${$countOffset} others like this';
}
```

The adjusted local is declared only when something reads it, so a message with
an offset and no `#` does not generate an unused variable.

### `#` inside a plural is not formatted, unless the project asks

ICU says `#` is rendered with the plural's number format. By default this
library interpolates the raw number instead.

The trade-off: honouring ICU would pull `intl` into every message containing a
plural, which is most apps — the exact dependency creep the design avoids.

So it is a project level switch rather than a default:

```yaml
format_plural_numbers: true   # default: false
```

When it is on, every `#` — in `plural` and in `selectordinal`, before and after
an `offset:` — renders through the locale's `NumberFormat.decimalPattern`, which
is the format ICU specifies for a plain plural argument:

```dart
return 'You have ${_enNumberDecimalPattern.format(count)} cards linked';
```

**The default does not change.** Flipping it changes the output of existing
messages (`1500` becomes `1,500`) and adds `intl` to a project that may have had
no formatting at all, so it cannot be silently correct for everyone. Both halves
are covered by goldens: the JSON fixture leaves it off and asserts that nothing
imports `intl`, the ARB fixture turns it on.

Nothing else changes with the flag. An explicit `{count, number}` was already
formatted and still is, so the per message opt-out is unchanged.

### Currency codes are explicit, and render as ISO codes

`{n, number, currency}` formats with the *locale's* currency, which makes a
price in US dollars impossible to render in a Russian locale — a real defect for
anything financial. Two spellings now set the currency, matching how the two
input formats are actually written.

In a message, as an extension of the style token:

```
{amount, number, currency:USD}
```

In ARB, as `gen_l10n` writes it, so a bundle exported from a TMS works unedited:

```json
"@price": {
  "placeholders": {
    "amount": {
      "type": "double",
      "format": "currency",
      "optionalParameters": {"name": "USD"}
    }
  }
}
```

Both land on `NumberFormat.currency(locale: ..., name: ...)`. The code is part
of the generated formatter's name, so `USD` and `EUR` in one locale are two top
level finals rather than one that silently wins.

**Why `currency:USD` and not the ICU skeleton `::currency/USD`.** The skeleton
is real ICU 60 syntax, and supporting one stem of it while rejecting `.00`,
`group-off`, `sign-always` and the rest would be worse than not claiming it:
users who know skeletons would write valid ICU and get "unknown style". The
supported spelling is visibly ours. A message that does use a skeleton gets a
diagnostic naming the spelling that works, rather than a generic style error.

**The code must be three upper case letters**, checked at both entry points. The
assigned set changes over time, so the shape is validated here and the meaning
is left to `intl`. A code on a style that cannot use one (`percent:USD`,
`yMMMd:USD`), a code on a plural or select argument, and a message and its
metadata naming two different currencies are all errors — the failure mode being
prevented is money rendered in the wrong currency.

**Code or symbol is a second style, not a flag.** `currency` renders the ISO
code (`USD1,234.50`, `1 234,50 USD`); `simpleCurrency` renders the locale's
symbol for that currency (`$1,234.50`, `1 234,50 $`). Both are real `intl`
constructors and both take a code, so the pair reads the same way in a message
and in ARB:

```
{amount, number, currency:USD}         →  USD1,234.50
{amount, number, simpleCurrency:USD}   →  $1,234.50
```

Neither is the default for the other: `$` is ambiguous across USD, CAD and AUD,
which is why `intl` prints the code unless asked otherwise, and a finance app
usually wants exactly that. A shopping app usually wants the symbol. Making it
a style rather than a boolean keeps the choice per message, which is where it
actually varies, and costs nothing — the style allowlist already existed.

### The remaining `optionalParameters`: symbol and decimalDigits

`NumberFormat.currency` takes `symbol:` and `decimalDigits:` besides `name:`,
and ARB carries them under the same names. Both are honoured:

```json
"optionalParameters": {"name": "BTC", "symbol": "₿", "decimalDigits": 8}
```

`decimalDigits` is the one that silently produces wrong money: a bundle asking
for `0` and getting the currency default renders `$1,234.50` where the author
wrote `$1,235`. It is validated as a whole number in `0..20` — `NumberFormat`'s
own limit — and accepted as `2` or `"2"`, because hand written ARB uses both.
`symbol` is arbitrary text, so it is escaped into the generated string literal;
a `$` in a symbol would otherwise emit an interpolation and fail to parse.

Everything that distinguishes one formatter from another is part of its field
name — `_enNumberCurrencyUsdDigits2` versus `_enNumberCurrencyUsdDigits0` —
because a formatter is shared across every message that asks for the same
thing, and collapsing two different requests onto one final would let the last
one emitted silently win. The symbol is hashed into the name rather than
spelled out, since it is not an identifier.

`customPattern` is **not** passed through. It is a raw ICU decimal pattern that
`NumberFormat` only rejects when the app runs, and a build time generator that
can produce a runtime throw is worse than one that says no. It gets the
`unsupported_optional_parameter` warning.

`symbol` belongs to `currency` alone. `NumberFormat.simpleCurrency` has no
`symbol:` parameter — deriving the symbol *is* the difference between the two
constructors — so a symbol declared there is an error rather than an argument
the generated file would fail to compile with. The emitter carries a matching
guard, and both live next to each other on purpose.

These two are ARB only. JSON has no metadata layer at all — no types, no
descriptions, no examples — so this is the existing split rather than a new
one, and `simpleCurrency` covers the case a JSON project usually needs. Packing
them into the style token (`currency:USD/₿/8`) would invent a grammar with no
ICU precedent for two attributes that a bundle already knows how to carry.

### Currency settings are per locale; the format is not

The base locale decides *whether* an argument is money and how its Dart type is
spelled. That is the API contract, and it cannot vary. Which currency, with
what symbol and how many fraction digits, is presentation, and a bundle is
entitled to its own:

```json
// app_ru.arb — roubles are quoted without kopecks
"@wallet.localPrice": {
  "placeholders": {"amount": {"optionalParameters": {"decimalDigits": 0}}}
}
```

Each locale's declarations are merged over the base's, so a bundle states only
what it changes, and a bundle that declares nothing renders exactly as the base
says. `MessageModel.currencyOverrides` carries them per locale tag, and the
emitter folds them into the format for that locale only.

Divergence is reported **only when both locales name an explicit and different
currency code**. Different digits or a different symbol are the intended use —
roubles without kopecks beside dollars with cents is the reason the feature
exists — so warning there would fire on every correct bundle. Two locales
quoting genuinely different money is worth a look, and gets
`currency_options_mismatch`.

The style may vary too. What may not is the argument's **kind**: `number`
versus `date` decides the Dart type, and the signature is shared. So a locale
may declare `simpleCurrency` where the base declared `currency`, inheriting the
currency and the digits and changing only how the amount is spelled, while a
locale declaring `yMMMd` on a number is an error naming the styles that do
apply.

Precedence is one rule, the same in every locale: **the message beats the
metadata.** What the string writes decides the style for its own locale; only
then does that locale's declaration apply, and only then the base's. Currency
settings are folded in on top either way, so a bundle can pin its own currency
without restating the style.

That rule has a consequence worth stating: an override only reaches a message
that writes its placeholder plainly. A project whose base locale writes
`{amount, number, currency}` in the string has already decided the style there,
and cross-locale validation requires every locale to write the same kind. The
per locale style is therefore a feature of ARB shaped projects — the `gen_l10n`
shape, where messages say `{amount}` and metadata says the rest. The example
app has a JSON base, so it exercises the currency settings but not the style;
the ARB and `formats` golden fixtures cover the style, and are type checked
*and executed* against real `intl`.

Locales may disagree about the currency — a Russian message legitimately quoting
roubles where English quotes dollars is not an error, so it stays the existing
`format_style_mismatch` warning.

### Placeholder type is `String` unless declared

`{name}` generates `required String name`. `Object` would be friendlier and
weaker; the point of the library is that wrong arguments fail to compile.

A format that can declare types overrides that default: ARB's
`"placeholders": {"count": {"type": "int"}}` generates `required int count`.
That holds whether the formatting is written in the message or declared beside
the type — `{"type": "double", "format": "currency"}` generates
`required double amount`, the same signature `{amount, number, currency}` would.
The two paths disagreeing was the bug: the metadata path used to widen every
declared numeric type to `num`, so the same declaration produced a different
API depending on where the format was written.
Only types that render correctly with `toString` are accepted — `String`,
`Object`, `int`, `num`, `double`, and the numeric three on plural arguments.

`"type": "DateTime"` requires an explicit `"format"`. A date has no single
correct rendering, so guessing one would silently produce output the author
never chose; the diagnostic names the alternatives. Given a format, an ARB
bundle that writes `{when}` in the message and puts `yMMMd` in the metadata —
what `gen_l10n` produces — generates correctly without editing any message.

### Argument conflicts compare type families, not kinds

`"On {d, date, short} at {d, time}"` is one `DateTime` argument used twice, so
conflict detection compares the Dart *type family* (`text`, `number`,
`dateTime`, `enumeration`) rather than the ICU kind. A plain `{count}` inside a
plural branch carries no type information and always yields to the plural.
`{x, number}` together with `{x, date}` is a genuine error: no single parameter
can be both.

### One locale, several files

A file path has to answer two questions: which locale is this, and which part
of the name is *not* the locale. A bare base name cannot answer both — `app_en`
is itself a valid tag, so guessing which half is a prefix picks the wrong
locale in silence. `file_pattern` says it instead:

```yaml
file_pattern: "{locale}"               # default: en.json
file_pattern: "app_{locale}"           # app_en.arb
file_pattern: "{namespace}_{locale}"   # auth_en.json    → t.auth.*
file_pattern: "{locale}/{namespace}"   # en/wallet.json  → t.wallet.*
file_pattern: "*_{locale}"             # auth_en.arb, keys written in full
file_pattern: "**/{locale}"            # wallet/settings/en.json
```

The rest of the name is one of two things, and which one is the decision worth
recording:

* `{namespace}` — the capture becomes a namespace the file's keys go under, so
  `auth_en.json` holding `{"login": {...}}` generates `t.auth.login`. Dots
  nest: `wallet.settings_en.json` gives `t.wallet.settings`.
* `*` and `**` — matched and discarded. The file writes its keys in full and
  the files merge. `**` crosses directories, `*` does not.

Both exist because the two formats want opposite things. A hand written JSON or
YAML file should not have to repeat `auth` inside `auth_en.json` — that is what
`i18next` and `slang` avoid, and it is the common case here. But a bundle
exported from a TMS already has fully qualified keys (`auth.login.title`), so
prefixing it by file name would produce `auth.auth.login.title`, and the format
we support best would be the one the feature fought.

One placeholder either way would have broken half the projects that use this.
Two cost one branch in the matcher and one sentence to explain, which is
cheaper than a layout a project cannot express.

Nesting happens **before** merging: a matched namespace wraps the file's tree,
and then every rule that governs several files of one locale applies to the
result unchanged. So `wallet_en.json` and `wallet.cards_en.json` merge exactly
as two files writing `wallet` in full would — the `split` golden fixture was
converted from the `*` layout to `{namespace}` and its generated output did not
change by a single byte.

Merging follows one rule: **groups merge, leaves collide.** Two files both
contributing to `wallet` is the point; two files both defining `wallet.balance`
is a mistake that would otherwise be settled by whichever was read last. A key
that is a group in one file and a message in another is `conflicting_key_kind`.
Files are read in sorted path order, so the merged order — and therefore the
generated output — never depends on the file system.

The pattern is a claim only when the project makes it. Under the default,
`app_en.arb` "matches" as the locale `app_EN` and `@@locale` quietly corrects
it, which is exactly what makes a `gen_l10n` bundle work unedited. Configure a
pattern and the claim becomes real: a file whose declared locale disagrees with
its path gets `locale_pattern_mismatch`, and a file matching nothing is skipped
with the pattern named rather than ignored.

This is a build time concern only. Once merged, a locale is the same tree it
would have been in one file, so the golden fixtures are the right level of
proof and there is nothing extra to execute. The `split` fixture generates from
three files per locale in two formats.

### YAML: two things that are not JSON with less punctuation

`package:yaml` is already a dependency and is span aware, so unlike JSON this
parser has no hand written scanner behind it. Two things still need care.

**Implicit typing.** `package:yaml` implements YAML 1.2, so the YAML 1.1
booleans `yes`, `no`, `on` and `off` really are strings — rejecting them would
reject valid translations, and a diagnostic warning about them would be wrong.
`true`, `false`, `null`, `~` and anything numeric are *not* strings, and a
translation that reads as one of them silently stops being text. That gets a
diagnostic naming what the value became. The list is checked by tests in both
directions, because it is the kind of thing that is easy to write from memory
and get wrong.

**Scalar styles.** ICU diagnostics point *inside* the message, which needs the
offset of its first character. A plain scalar's span is exactly its content, a
quoted scalar's includes the quotes, and a block scalar's includes the
indicator and re-folds the text. The offset is therefore computed only where it
is provably right — the source text equals the value, or equals the value in
one pair of quotes — and left null otherwise, which falls back to the whole
value span. Same rule the JSON parser uses for escapes: a wrong position is
worse than a coarse one.

An ICU message often starts with `{`, which YAML reads as a flow mapping, so
messages are usually quoted. Single quotes escape by doubling — exactly as ICU
does with apostrophes — which is a good way to get a parser wrong, and has its
own test.

YAML carries no metadata: there is no natural place for ARB's `@key` in a
nested document, and inventing one would be guessing at a convention nobody
writes yet. Like JSON, it takes its locale from the path.

The `yaml` golden fixture is the JSON fixture's messages, transcribed. Its
generated output is asserted **byte for byte identical** to the JSON one, which
is the strongest thing the parser seam can say: two formats in, one API out.

### ARB locale detection

ARB declares its own locale, and `@@locale` wins over the file name. That is
what lets `app_en.arb` — the name `gen_l10n` writes — be read correctly even
though `app_en` is itself a valid locale tag. Formats that cannot declare a
locale, such as plain JSON, must be named after it.

This is why `TranslationSourceParser.parse` takes a locale *hint* rather than a
locale: deciding the locale is format knowledge, so it lives in the format
layer.

### ARB nesting

ARB is flat. Dotted keys expand into namespaces: `auth.login.title` generates
`t.auth.login.title`, and a key with no dots stays at the top level, which is
what a bundle exported from `gen_l10n` or a TMS looks like. A key that is both a
message and a group prefix is an error.

### `setLocale` is synchronous

The prompt sketched `await controller.setLocale(...)`. Nothing is loaded
asynchronously in generated mode, so returning `Future<void>` would be a lie
that exists only to support a loader that does not exist yet. It is `void`. If
network or OTA translations arrive, they get their own async API.

### No `LocalizationsDelegate` in the MVP

`L10nScope` + `L10nController` is a single source of truth for the active
locale, and `MaterialApp.locale` is driven from it. Adding a delegate would
create a second path to the same state. Apps still add
`GlobalMaterialLocalizations.delegates` for Flutter's *own* widgets — that is
not this library's job, and the example shows it.

### `date` is permissive about skeletons, `time` is not

`DateFormat` skeletons are one namespace, so nothing stopped `{t, time, yMMMd}`
from resolving — it compiled, and rendered a date with no time in it. The
skeleton set is split: `time` accepts the clock skeletons and its own named
styles, `date` accepts everything.

The asymmetry is deliberate rather than tidy. `{d, date, jm}` is odd but has
always been accepted and renders exactly what it says; rejecting it would break
working projects for no benefit. `{t, time, yMMMd}` silently drops what the
author asked for, which is the failure this library exists to make impossible.

### The generated code is analyzed, not just diffed

Golden tests compare text. Text can be wrong in a way no diff notices: for two
milestones `{n, number, integer}` emitted `NumberFormat.integer(...)`, which
does not exist, and `simpleCurrency` accepted a `symbol:` it has no parameter
for. Both produced files that would not compile, and neither test caught it —
the goldens were excluded from analysis, and the generator does not depend on
`intl` at all.

Three things now hold that line:

* `intl` is a **dev** dependency of the generator. Nothing in `lib/` imports
  it; it exists so the goldens resolve.
* `test/goldens/**` is no longer excluded from the analyzer, so `dart analyze`
  type checks generated output against the real `package:intl`.
* `test/goldens/formats/` is a golden whose input is **derived from
  `IntlFormatters` itself** — every number style, every date and time style,
  every skeleton, and the currency option combinations only ARB can express.
  Adding a style to an allowlist extends the fixture automatically, and the
  golden diff says so.

Analysis proves the calls exist and type check. It does not prove they render
anything in particular — dropping `decimalDigits` from the emitted argument
list compiles, analyzes clean, and quietly turns `USD1,235` into `USD1,234.56`.
So the surface golden is also **executed**: `goldens_runtime_test.dart` imports
it like any other library and asserts real `intl` output, including the
rounding of `integer`, the per locale restyle, and that a `$` in a declared
symbol survived escaping.

That works because the golden is ordinary Dart in the generator's own `test/`
tree, and the package already has `intl` and `l10n_plus` on hand. No second
app, no Flutter, and the file that is executed is byte for byte the file that
is analyzed.

The example app executes generated code too, but only what a demo happens to
use, and it is shaped as a demo rather than as coverage. The two are
complementary: the example proves the Flutter integration, the runtime golden
proves the formatters.

### One generated file per locale

`file_per_locale: true` splits the library into a shared file — imports, the
locale enum, the select enums, the interfaces, the date symbol initializer —
and one file per locale holding that locale's implementation classes and the
formatters only it uses. Editing a Russian string rewrites one file.

**`part`, not separate libraries.** Both would work; parts win on three counts.
The formatters are private top level finals, and parts keep them private *and*
reachable, where separate libraries would have to make them public or duplicate
them. The shared file names `const AppLocalizationsEn()` and each locale needs
the interfaces, which between libraries is an import cycle — legal in Dart, but
noise. And decisively: **the import an application writes does not change.**
One library, one import, whichever way the option is set — so turning it on is
not a migration, and the generated Flutter glue is byte for byte identical.

The cost is that a `part` cannot have its own imports, so every import lives in
the shared file. That is fine here: the generated code imports `l10n_plus` and,
when something formats, `intl` — and the "no formatting, no intl" rule still
holds, now over the union of the locales.

**`build_runner` declares output extensions statically**, and the set of
locales is only known once the translations are read, so the builder cannot
discover them. It does not try: outputs are listed in `build.yaml`, and a file
the generator wanted to write but could not is reported by name with the exact
block to paste. The CLI has no such constraint. That is the honest split —
`build_runner`'s rule is not something an adapter can paper over, and guessing
would fail at the wrong moment.

Splitting changes which file a declaration lands in and nothing else: the same
interfaces, the same members, the same order. The `split` fixture generates a
three-files-per-locale project into one file per locale, and because the
goldens are analyzed the `part` wiring is type checked; `goldens_runtime_test`
then runs it, so the `const` graph is proven to resolve across part boundaries.

### Unused keys: a text scan, and why not the analyzer

`dart run l10n_plus_generator unused` reports base locale messages that no Dart
source refers to. The generated API is a chain of getters, so a message is used
exactly when its member name appears after a dot somewhere, and that is what
the scan looks for: every `.name`, `?.name` and `..name`, as text.

**It over-approximates use on purpose.** Two keys called `title` are
indistinguishable to it, so if either is used both count as used. That is the
wrong answer in the harmless direction. The expensive mistake is the other one
— calling a live translation dead and having someone delete it — and this scan
cannot make it: everything it reports is a key whose member name appears
nowhere in the searched code.

Resolving the project with `package:analyzer` would be exact. It would also put
the heaviest package in the ecosystem into every consumer's dev dependencies to
answer a question that is advisory by nature, and it would be slow enough that
nobody would put it in CI. The trade is deliberate, and the limitation is
written into the diagnostic rather than hidden: it names the member it looked
for and how many files it searched.

**The output directory is excluded**, along with `.dart_tool` and `build`.
Generated code declares `get balance` and its locale enum writes `.en`, so
counting it would make every key look used forever. This is the one exclusion
that is a correctness requirement rather than a speed one, and it has a test.

**Why a command, not a builder.** The roadmap expected this in the
`build_runner` adapter, since that has the package's sources as assets. On
inspection it is the wrong home: the generated file lives in `lib/`, so
scanning `lib/**` would make a builder read its own output, and every unrelated
code edit would invalidate the translations. It is also a report rather than a
build step — a commented out widget should not fail your build. The CLI has
none of those problems, and `unused` exits non-zero so CI can still enforce it.

### Untranslated keys: fail, or fall back

A key the base locale defines and another locale does not is an error by
default. That is right for a finished project: the base locale is the API
contract, and a silently missing string is how `Instance of 'Null'` reaches a
screen.

It is wrong for a working one. Translations arrive after the code, so a team
that ships an English string on Monday and gets the Russian one on Thursday
cannot build in between. `fill_missing_from_base: true` turns the error into a
warning and generates the message anyway.

**What falls back is the whole message, not just its text.** An untranslated
message renders exactly as the base locale renders it: base text, base plural
rules, base number formatting. The emitter builds that member with the base
locale as its rendering context, which is one substitution rather than a second
code path.

The alternative — English words under Russian plural rules — would produce
"2 card", and English words with Russian digit grouping would produce
"Total: 1 234,5". Both are worse than an obviously untranslated string, because
both look deliberate. A missing translation should read as missing.

What the option does **not** excuse: a key the base locale does not have
(`extra_key`), a translated key whose arguments disagree with the base
(`missing_placeholder` and friends), or a missing base locale. Those stay
errors, because none of them can be filled in from anywhere.

The `fill_missing` golden fixture is a Russian locale with one key of six, so
the fallback paths are generated and — since the goldens are analyzed — type
checked.

## Benchmarks

`example/benchmark/l10n_benchmark.dart`. Each generated call is measured
against a flat `Map<String, String>` — the runtime map the design rejected —
so that decision is a number rather than an assertion. The map baseline is
favourable to the map: pre-joined keys, no nesting to walk, no argument
checking.

Dart VM, JIT, one machine. Read the ratios, not the absolutes.

| | generated | flat map |
| --- | --- | --- |
| getter, three namespaces deep | 3.6 ns | 7.5 ns |
| interpolation, one argument | 20.5 ns | 78.5 ns |
| plural, CLDR branch | 21.8 ns | 74.9 ns |
| select, generated enum | 21.5 ns | — |
| number, shared `NumberFormat` | 295.7 ns | — |
| locale fallback resolution | 308.3 ns | — |

What the numbers say:

* **Namespace access is a field read.** `identical(t.auth, t.auth)` is `true`,
  so there is nothing to time and nothing to allocate; the 3.6 ns is the
  `switch` over the locale enum the benchmark cycles through to stop the loop
  folding, not the access.
* **The map is not catastrophically slower, it is consistently slower** — and
  it gives up the compile time argument checking that is the actual point.
  Anyone choosing a map should do it for generated file size, not speed.
* **Formatting dominates everything else.** A `NumberFormat.format` call costs
  more than ten plural branches, which is why the formatter is a shared top
  level final rather than built per call, and why `intl` is kept out of
  projects that never format.
* **Locale resolution is parsing.** Most of the 308 ns is `L10nLocale.parse`
  turning a string into a locale. Apps resolve on a locale change, not per
  message, so this is the number least worth optimizing.

**The first run of this benchmark measured nothing.** With a constant argument
the JIT hoisted the whole call out of the loop and interpolation "cost" 1.7 ns
— faster than the field read next to it, which is what gave it away. Every case
now cycles its inputs. The lesson is in the file, next to the code that
prevents it.

A test runs every case once, so the benchmark cannot rot unnoticed. No timing
is asserted: a threshold that fails on a slow CI box teaches people to ignore
it.

Not measured: `context.l10n` lookup and locale switch rebuild cost. Both need a
Flutter harness, and both would mostly report Flutter's costs —
`dependOnInheritedWidgetOfExactType` and the app's own rebuild — rather than
this library's.

## Determinism

Identical inputs produce byte-identical output:

* translation files are sorted by path before reading;
* locales are sorted by file tag;
* namespaces and messages follow base-locale document order;
* select enums are sorted by name;
* exact plural cases are sorted by value, categories follow CLDR order;
* output is run through `dart_style` at the current language version.

A golden test asserts the output, and a second test runs the pipeline twice and
compares. Unchanged files are not rewritten, so watchers see no churn.

## Diagnostics

`Diagnostic` carries a severity, a stable `code`, a one-line message, a
`SourceSpan`, the dotted translation key, and multi-line `details` that state
the expectation and what was found:

```
translations/ru.json:11:22
wallet.transactions
error[missing_placeholder]: Argument "count" is missing.
  Base locale en:
    argument: count
    type: plural
  ru locale:
    argument is missing
   ╷
11 │     "transactions": "Транзакции",
   │                      ^^^^^^^^^^
   ╵
```

Spans point *inside* the message, not just at the file, because the JSON parser
records where each string's contents start. When a string literal contains
escape sequences the offsets no longer line up, and the parser falls back to the
whole-value span rather than reporting a wrong position.

## What is intentionally not here

Network/OTA translations, TMS integrations, PO/XLIFF/XML/TOML, an IDE
plugin, a hot-reload daemon, a translation editor, and dynamic string-keyed
lookup. See `docs/roadmap.md` for the order they are expected in.
