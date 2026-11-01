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
the number, so "2.5 stars" cannot be selected correctly from an `int`, and
`count: 5` still compiles against a `num`. `PluralOperands` computes
`n, i, v, w, f, t` from the `num`.

**Where a `num` cannot say what CLDR asks.** The operands are about how the
number will be *displayed*: CLDR distinguishes `1` from `1.0` by `v`, the count
of visible fraction digits. A Dart `num` does not carry that — `1.0` and `1`
are the same value — and `PluralOperands` resolves it by treating anything
equal to its own truncation as having no fraction digits, so `v` is 0 for both.

The consequence is narrow and real: `1.0` selects `one` in English where CLDR
says `other`, and Czech `many` (`v != 0`) is unreachable for a whole number
written as a double. It only shows for a `double` argument with a zero
fraction; every genuinely fractional value has the operands CLDR expects, and
integer arguments — nearly all of them — are exact.

This is why the CLDR sample check leaves out `@decimal 1.0` style values: they
are values this runtime cannot be handed, and a test that pretended otherwise
would be asserting the wrong thing.

That is the story for a count nobody formats, and it is still the default.
Where a formatter *is* attached the ambiguity disappears, and the operands come
from it instead — `PluralOperands.formatted`, below.

#### What the rest of the ecosystem does, measured

`intl` has the same problem and answers it with a `precision` parameter on
`Intl.plural`. Reading `intl-0.20.3` and running it:

| call | result |
| --- | --- |
| `Intl.plural(1.0, one: …, other: …)` | `one` |
| `Intl.plural(1.0, …, precision: 0)` | `one` |
| `Intl.plural(1.0, …, precision: 2)` | `other` |

`precision` defaults to nothing, and `pluralLogic` then truncates a whole
double to an `int` before selecting — deliberately, so that "1.0 and 1 produce
the same output, e.g. 1 dollar". That is exactly what `PluralOperands` does.
`gen_l10n` never passes `precision` at all (`pluralVariableTemplate` in
`gen_l10n.dart` has no slot for it), so **every Dart localization tool in
existence selects `one` for `1.0`.** This library is not diverging from CLDR
alone; it is bug-compatible with the whole ecosystem, which is a much cheaper
position to hold than it looked.

#### `precision` is the wrong shape of the answer

The operand `v` is not a property of the value and not a property the caller
knows: it is a property of **the formatter that will render the number**.
`NumberFormat.currency(locale: 'en')` has `minimumFractionDigits == 2`, so it
renders `1` as `USD1.00` and CLDR then says `other`. `NumberFormat
.decimalPattern('en')` has `minimum 0, maximum 3` and renders the same `1` as
`1`, where CLDR says `one`. One value, two correct answers, decided entirely by
the format.

So `precision` asks the caller to restate, at every call site, something the
*generator* already knows — and gets it wrong whenever the two drift apart.
This answers the question the roadmap asked: value and rendering can be told
apart without a second parameter in every signature, but only where the format
is declared in the message. For a number the caller formats themselves and
passes in pre-rounded, nothing short of a parameter can help, and that case is
already outside what this library renders.

#### The defect this closes, in the tool next door

The correct-`v`-needs-the-formatter defect is reachable in `gen_l10n`. Running
it on a plural whose count declares `"format": "currency"` produces:

```dart
final String countString = countNumberFormat.format(count);   // USD1.00
String _temp0 = intl.Intl.pluralLogic(count, locale: localeName,
    other: '$countString cards', one: '$countString card');   // one
```

— "USD1.00 card", the failure `intl`'s own documentation warns about.

It was never reachable here, but only by accident: the generator **silently
discarded** the `format:` on a plural count, so no formatter with fraction
digits could reach one. That is not a guarantee, it is a hole that happened to
point the safe way, and it cost the author the rendering they asked for.

Honouring the declaration is what closes both at once — the feature and the
operand question — because a formatted count has no ambiguity left about what
`v` should be.

**Chosen: the operands follow the formatter that renders the count.**

A format declared on a plural count is honoured — the count renders through it
and `PluralOperands.formatted` reads the operands off the digits it produces:

```dart
String cards({required num count}) {
  final $operands = PluralOperands.formatted(
    count,
    minimumFractionDigits: _enNumberCurrency.minimumFractionDigits,
    maximumFractionDigits: _enNumberCurrency.maximumFractionDigits,
  );
  if ($operands.i == 1 && $operands.v == 0) {
    return '${_enNumberCurrency.format(count)} card';
  }
  return '${_enNumberCurrency.format(count)} cards';
}
```

`cards(count: 1)` is `USD1.00 cards`, where `gen_l10n` prints `USD1.00 card`.
Executed, not read: `goldens_runtime_test.dart` runs the generated file.

**The bounds are read at run time, not baked in.** `NumberFormat.currency`
takes its fraction digits from the currency — JPY has none, USD has two — and
the generator does not know which currency a bundle names. So the emitted code
reads `minimumFractionDigits` and `maximumFractionDigits` off the formatter
field. The runtime stays free of `intl`: it receives two `int`s.

**Only where the count is actually displayed through the formatter.** A plural
of pure words (`one{Delete the file} other{Delete the files}}`) shows no number
at all, and a branch that interpolates `$count` raw shows `toString()` — which
is what the value based operands already read. Emitting formatter operands
there would claim digits nobody sees, so the emitter walks the branches and
uses the format only if some `#` or `{count}` renders through it.

**`format_plural_numbers` is included, on the same principle.** When that flag
renders `#` through the locale's decimal pattern, that pattern decides the
visible digits, so the operands come from it too. This is the one behaviour
change beyond the declared format case, and it is small and in the same
direction: the pattern rounds at three fraction digits, so a count of
`1.23456` now has `v == 3` and `f == 235` — what `1.235` displays — instead of
`v == 5` from a value nobody sees. Leaving it out would have reintroduced the
exact mismatch this section is about.

**What did not change.** A count with no formatter still reads its value, so
`1.0` still selects `one` in English, still matching `intl` and `gen_l10n`.
That question only had a wrong answer because the number was invisible; with a
formatter attached it is not a question at all, and `PluralOperands.formatted`
gives `1.0` under a decimal pattern the operands of `1`, and under a currency
the operands of `1.00`. Same value, two answers, both correct.

**`dropped_placeholder_format` survives for select arguments**, which choose a
branch and have no number to format. That declaration really is dropped, and
saying so is the rule everywhere else here.

### Plural rules: runtime table vs generated conditions

**Chosen: generated conditions.** The generator knows the locale it is emitting,
so it inlines that locale's rule as Dart:

```dart
final $operands = PluralOperands(count);
if ($operands.v == 0 && $operands.i % 10 == 1 && $operands.i % 100 != 11) {
  return '$count транзакция';
}
```

No rule table ships to the app, and there is no per-call rule dispatch. An
unknown language produces `unknown_plural_language` rather than silently
falling back to English rules, which is the classic way localization libraries
ship wrong plurals.

**The table is the whole of CLDR, and is generated.** It began curated — about
forty languages someone had transcribed — and that was a wall rather than a
safeguard: `bg`, `sl`, `lv`, `fa`, `ta`, `mr` and a hundred others could not be
added to a project at all, and the diagnostic that explained why had no fix
under it. `tool/update_cldr_plural_rules.dart` now compiles `plurals.json` and
`ordinals.json` into the same condition format: 222 cardinal languages and 107
ordinal ones, from CLDR 48.

Two CLDR subtleties are compiled in rather than left to whoever transcribes
next:

* **a range matches integers only** (UTS #35), so `n % 100 = 3..10` is `few`
  for 3 and `other` for 3.5. `@n == @i` is what says "n is an integer" in terms
  of the operands, and it is emitted into every range condition over `n`. The
  hand written table had this wrong for Arabic, which is exactly the failure
  mode the curation was supposed to prevent: it compiled, it analyzed, it
  rendered a plausible sentence, and it was wrong in a language nobody on the
  team reads;
* **the operand `e`**, the exponent of a compact form, is always 0 here because
  nothing formats compactly before selecting a branch. Relations over it are
  decided at generation time and never reach the output, which is why the
  Romance `many` is three clauses rather than five.

Two independent oracles check the result, and they are complementary rather
than redundant:

* **CLDR's own samples.** Every rule carries `@integer` and `@decimal` lists
  naming values that must land in that category; 2698 cardinal and 1044 ordinal
  values are run through the *generated code* and compared. They come from the
  release the conditions were generated from, and they cover all 222 languages.
* **`package:intl`.** It carries its own copy of the rules, generated from ICU
  data, so it is a second implementation. It covers 89 of the 222 and answers
  `other` for the rest — which would read as agreement, so languages it does
  not carry are excluded rather than compared.
* **ICU itself, for ordinals**, where `intl` has no table at all.
  `Intl.PluralRules(locale, {type: 'ordinal'})` in Node is that table, and
  `tool/ordinal_oracle.sh` dumps its answers into
  `test/data/cldr_ordinals.json`. The answers are vendored rather than
  queried, so the suite needs nothing but Dart; the script exists so the file
  can be regenerated and argued with.

Neither alone is enough. CLDR's samples for Arabic `few` are all integers and
whole decimals, so deleting the integer guard passes them; `intl` catches it at
3.1. `intl` computes the operand `i` as `n.round()` where CLDR defines it as
the integer digits, so it reads 1.5 as `i = 2` and is wrong for Danish, French,
Portuguese and Hindi fractions; CLDR's samples are right there. Both are in the
suite, and the guard was verified by regression against both.

Script and region qualified CLDR entries (`pt-PT`, `kok-Latn`) are left out:
rules are looked up by language subtag, so nothing could reach them.


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

### One registry for every top level name

The `$` prefix separates enums from namespaces. It does not separate namespaces
from each other, and that is where the generator used to emit a file that did
not compile:

```json
{"auth": {"login": {"title": "A"}}, "auth_login": {"title": "B"}}
```

`auth.login` and `auth_login` both normalize to `$AuthLogin`. Collisions were
checked per namespace — two members of one class — and between select enums,
and neither check sees this. The generator wrote the file without a diagnostic
and `dart analyze` reported `duplicate_definition` in generated code, which
reads like a generator bug because it is one.

Dart puts classes, enums, interfaces and top level functions in **one**
namespace, so there is one registry to match. Everything is claimed in
generation order: the class name, the locale enum, each locale's implementation
of the root class, each namespace interface, each namespace's implementations
(`$AuthLoginEn`, `$AuthLoginRu`), and each select enum. A second claim on a
taken name is an error naming both sides and pointing at the second key.

Two details are worth the words:

* **the implementations are claimed only when the interface was free.** A
  colliding pair in a ten locale project would otherwise be eleven errors for
  one rename;
* **the code depends on what collided.** A select enum on either side keeps
  `enum_name_collision`, which that case has always reported. Everything else
  is `type_name_collision`, which is new because the collision was previously
  undetectable rather than differently named.

The registry also covers the case the `$` prefix does *not* handle: a namespace
whose interface takes the name of another namespace's implementation, so
`foo.en` collides with `$FooEn` in a project that has an `en` locale.

### Object graph: `const`, not lazy fields

Namespace accessors return `const` instances:

```dart
@override
$AuthLogin get login => const $AuthLoginEn();
```

Every namespace object is canonicalized at compile time, so `context.l10n.auth.login.title`
allocates nothing and holds no back-reference to its root. A `late final` field
per namespace would allocate once per locale; `const` allocates zero times. The
The prediction written here used to be that this costs linked translations, and
that the feature would need a root reference when it arrived. Milestone 33
disproved it: a link names the target's implementation class directly —
`const $BrandEn().name` — and a `const` constructor with no fields is free to
name from anywhere. The `const` graph was never the obstacle; believing it was
is why the feature waited.

### A link is resolved while generating, and the `const` graph survives it

`@:other.key` is the one construct in a message that reads another message, and
the whole performance argument of this library is that reading a translation is
reading a `const`. So a link never becomes a lookup. It becomes one of two
things, decided per link:

* **the target's text, written in place**, when the target takes no parameters
  and resolves to literals — the product name, the word a dozen messages share.
  Transitive, so a chain costs nothing either, and the result is byte for byte
  the file you would get from writing the words out. `link_test.dart` asserts
  exactly that, with the doc comment stripped: the doc comment deliberately
  still shows `@:brand.name`, because it documents the message as the
  translation file writes it.
* **a call on a `const` receiver**, when the target takes parameters, or when
  `runtime_overrides` is on. `const $BrandEn().name` — the target's own
  implementation class, named directly. Dart canonicalizes the instance, so
  this is one method call and no allocation.

The second form is why the prediction in
[Object graph: `const`, not lazy fields](#object-graph-const-not-lazy-fields)
was wrong. That note said a link would need a root reference and so would cost
the `const` graph. It does not: the generated classes have no fields, so naming
one from anywhere is free, and no `_root` pointer exists anywhere in the output.
`slang`, which does carry one, resolves every link through it at run time.

**`runtime_overrides` decides which form.** With overrides on, inlined text
could not change when the target is overridden, and a brand rename that reached
one message out of twelve would be worse than no feature at all — so the link
becomes a call and one bundle entry moves everything that links to it. With
overrides off there is nothing to override and the text goes in place. The two
features genuinely pull in opposite directions here; the configuration already
says which world the project is in, so nothing new had to be invented to ask.

**What a link lends is typed; what it brings is not overridable.** The target's
parameters become the linking message's parameters, merged through the same
`argument_kind_conflict` machinery two references in one string go through — so
`{n, date}` here and a plural called `n` there is an error, reported against the
link, with the details naming the message the other kind came from. The lent
parameter is a normal token in the override path, which is how a message that
never wrote `{n}` can still have a bundle place the count. The linked *text* is
not addressable: an override replaces one branch's words, and a link is resolved
before there are words.

### Links are validated against the project, not the string

`LinkResolver` answers four questions no single-message pass can:

1. **does the target exist** — `unknown_link_target`, with the nearest key
   offered from the same edit-distance budget the configuration and the override
   checker use. That routine is now one implementation in `nearest_key.dart`
   rather than the two copies it had grown into;
2. **is it a rich message** — `link_to_rich`. Spans are structure, and there is
   no string to splice;
3. **does the path lead back here** — `link_cycle`, with the ring written out in
   the order it is followed. Iterative DFS with colours, because the thing being
   looked for is unbounded depth and a stack overflow in the checker would be a
   joke at its own expense. A ring found from two directions is one finding, and
   so is a ring copied into twelve translation files;
4. **what do the targets contribute** — merged in dependency order, targets
   before the messages that link to them, so a chain is already settled by the
   time anything reads it and the transitive case needs no second pass.

It runs **per locale**, before cross-locale validation, because a translator can
write a link too and a link nothing defines is as wrong in Russian as in
English. The base locale goes first, so the one diagnostic about a mistake
copied into every file points at the file the project is maintained in. A locale
that writes the words out instead of linking produces the same signature and
passes; a locale that drops the lent parameter is the ordinary
`missing_placeholder`, which is the check already there.

For comparison, in the field: `slang` throws a bare string for a missing target
and guards cycles only in the pass that gathers parameters, so a ring emits code
that calls itself; `easy_localization` resolves links at run time, one level
deep, with `// TODO: add recursion detection and a resolve stack.` in its own
source.

**The sixth node kind.** `LinkNode` is the first addition to `MessageNode`
since the AST was written, and `rich_ast.dart` had warned that a sixth kind
would break every exhaustive switch over it. It did — six of them, across four
files — and the compiler named every one. That is the good kind of breakage: the
alternative to a sealed type here would have been a silent default branch in the
emitter.

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

**A format declared on the count wins over the flag**, and works without it: a
plural count that declares `"format": "currency"` renders as money whether or
not `format_plural_numbers` is on. The flag is the fallback for the counts
nobody declared. Either way the plural operands come from whichever formatter
ends up rendering the count — see `num` vs `int` for plural arguments above.

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
`yMMMd:USD`), a code on a select argument, a code on a plural count that
declares no currency format to spend it on, and a message and its metadata
naming two different currencies are all errors — the failure mode being
prevented is money rendered in the wrong currency. A plural count that *does*
declare `"format": "currency"` takes the code like any other money argument.

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

### The names `gen_l10n` writes are the same styles

The README promises an ARB bundle exported from `gen_l10n` generates without
editing a message. `"format": "decimalPattern"` — its spelling of the plain
decimal format — was met with `unsupported_placeholder_format`, which made the
promise false for the most ordinary formatted number there is.

`decimalPattern`, `percentPattern` and `scientificPattern` are now accepted as
spellings of `decimal`, `percent` and `scientific`, in a message and in ARB
alike. They are **folded at the entry points** — the ICU parser, the metadata
reader, and a locale's own override — rather than carried through as separate
styles, so everything downstream sees one style. That is what makes a project
mixing both spellings emit one formatter rather than two finals initialized
from the same constructor, and what makes every diagnostic name the canonical
spelling instead of echoing whichever the file used.

**`decimalPercentPattern` is not among them.** It reads like a spelling of
`percent` and is a different `intl` constructor: the one that takes
`decimalDigits`. Folding it onto `percentPattern` would compile, analyze, and
quietly render `43%` where the bundle asked for `42.56%` — the exact class of
silent wrongness the currency options were built to prevent. It is a style of
its own.

That made `decimalDigits` the first option that is not about money. The
validation splits accordingly: `name` and `symbol` still belong to the currency
styles alone, while `decimalDigits` is accepted by those four and by
`decimalPercentPattern`, and refused with a diagnostic naming the styles that
take it anywhere else.

`compactCurrency` and `compactSimpleCurrency` are added as full currency
styles rather than aliases, because they are genuinely different formats —
`USD1.2M` rather than `USD1,200,000.00`. The `simpleCurrency` rule carries over
unchanged: `compactSimpleCurrency` has no `symbol:` parameter for the same
reason `simpleCurrency` has none, so declaring one is an error rather than a
generated file that does not compile.

All of it lands in the formatter surface fixture automatically, because that
fixture derives its messages from the style allowlists — and the surface is
analyzed *and* executed, so the new constructors are type checked against real
`intl` and their output asserted.

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

**Checked again, September 2026, and the answer held.** `slang` is the closest
thing to a second opinion — it reads YAML, JSON, CSV and ARB, and it is
type safe, so it needs per placeholder types as much as this does. Its answer
is not `@key` in YAML. It writes the type *into the message*
(`"Hello {name: String}, you have {amount: currency}"`) plus an optional
file level `@@types` alias table, which is deduplication rather than new
expressiveness. And where it does support `@key` prose — JSON, ARB — its own
documentation says of YAML: "Currently, not parsed and no comments will be
generated."

So the convention that appeared is *metadata in the message*, which this
library already has in every format: `{n, number, currency:USD}` and
`{d, date, yMMMd}` parse identically out of YAML, JSON and ARB. The only thing
still unreachable from YAML is translator prose — `description` and `example` —
and the one library with a reason to have solved it declined to. Nothing to
copy. YAML stays metadata free.

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

### The system locale is read once, in the factory

`create<Class>Controller()` is documented as "omit the locale to follow the
operating system", and it did not. `systemLocales` defaulted to `const []`,
`L10nController` resolved that to the fallback locale, and Flutter calls
`didChangeLocales` only when the locale *changes* — never at start up. So on a
Russian phone the app opened in English and stayed there until the user changed
the system language and came back. The README and the example both used the
no-argument call, so the bug was in the recommended path.

The factory now reads
`WidgetsFlutterBinding.ensureInitialized().platformDispatcher.locales` when the
argument is omitted.

**`WidgetsFlutterBinding.ensureInitialized()`, not `PlatformDispatcher.instance`.**
Both give the platform's locales and the second needs no binding. The first is
what `flutter_test` can substitute: `tester.platformDispatcher.localesTestValue`
sets the value on the *binding's* dispatcher, and `PlatformDispatcher.instance`
would ignore it. A default that cannot be tested is a default that breaks
quietly, and this one already had. `ensureInitialized` returns the binding that
already exists rather than building a second one, so calling it from a test, or
after `runApp`, changes nothing.

The cost is that the factory binds the Flutter engine, so it must be called
from `main` or later. That is where a controller is built anyway, and the doc
comment says it.

`const []` still means "ignore the device", now as something a caller asks for
rather than as the only behaviour available.

### No `LocalizationsDelegate` in the MVP

`L10nScope` + `L10nController` is a single source of truth for the active
locale, and `MaterialApp.locale` is driven from it. Adding a delegate would
create a second path to the same state. Apps still add
`GlobalMaterialLocalizations.delegates` for Flutter's *own* widgets — that is
not this library's job, and the example shows it.

### The Flutter glue is on by default, and says when it cannot compile

`flutter.enabled` defaults to on, because most projects are Flutter projects
and a default that has to be switched on is a default that gets filed as a
bug. The cost falls on the other kind of project: a Dart consumer writing the
shortest configuration the CLI accepts used to get a second generated file
built out of `BuildContext` and `L10nScope`, and a screen of analyzer errors
in a file it never wrote.

So the glue is checked the same way `intl` is — by reading the consumer's own
`pubspec.yaml`. Generating it without `flutter` and `l10n_plus_flutter` in
`dependencies` reports `missing_flutter_dependency`, which names the one line
that turns it off and the two lines that make it compile. A warning, not an
error: a project may generate for a package it does not itself build.

### Region fallback is a rule, not the list order

`L10nLocaleResolver` walks the requested locale's lineage, then a region
sibling of the same language, then the fallback. Two things about the middle
step changed, and one deliberately did not.

What the lineage walk already gave, now guaranteed: it ends at the bare
language, so a supported locale with **no** region always beats a
region-carrying sibling — `en_NZ` against `en_AU, en_GB, en` is `en`, whatever
order those three are listed in. That held before as a side effect of
`lineage`, pinned only in passing; it is stated as a guarantee now and asserted
in three list orders.

What was wrong: with no bare `en` in the list, the winner was the **first**
sibling offered, so renaming a translation file could change what the app
rendered. The winner is now the minimum under a total order over the locales
themselves, which no ordering of `supported` can move:

1. **Script agreement.** `zh_Hant_HK` must read as `zh_Hant_TW` and not as
   `zh_Hans_CN`. Script is the one piece of real information available without
   CLDR's affinity table — orthography, not a guess about taste. A candidate
   carrying no script ranks between agreement and conflict, because it
   conflicts with nothing.
2. **The lowest tag**, as a tie-break that is stated rather than emergent.

What did not change: the library still claims no regional affinity. That a New
Zealander wants `en_GB` spelling is a table CLDR publishes and this library does
not carry; guessing it in code would be wrong in ways nobody could predict from
reading the source, and carrying the table would be a second CLDR dataset in a
runtime that has none. So `en_NZ` against `en_AU, en_GB` still resolves to
`en_AU` — now because `en-AU` sorts first and the resolver says as much, rather
than because `AU` happened to be listed first. The honest-looking alternative,
refusing to pick and falling through to another language, would render Russian
to a New Zealander with English translations sitting right there.

The test that asserted "reordering the list changes the answer" now asserts the
inverse. It pinned the defect on purpose, so fixing the defect had to flip it,
and the comment in the test says so.

### Direction is a script fact, and the fill is where it bites

`L10nLocale.isRightToLeft` is decided by the script and never by the region.
`ar_EG` and `ar` agree; the two Azerbaijani locales do not agree with each
other, because `az_Latn` and `az_Arab` are different scripts. An explicit
script subtag is the locale stating which script it is written in, so it is
taken at its word even when the language usually uses another — romanized Urdu
is left to right. Both lists come from one source, CLDR 46: a script is right
to left when `scriptMetadata.txt` says `rtl = YES`, a language when
`likelySubtags.xml` maps it to such a script. Written down because intuition is
unreliable here: Kurmanji Kurdish (`ku`) is Latin and absent, Central Kurdish
(`ckb`) is Arabic and present.

A predicate rather than an enum. The answer has exactly two values and both are
stable, so a `bool` carries all of it without putting a second type on the
runtime's public surface.

The reason to know direction at all is not layout — Flutter does layout — but
`fill_missing_from_base`. Filling a right-to-left locale with left-to-right base
text produces the worst kind of defect this library can produce: a screen that
looks finished. The sentences are complete and grammatical, so a reviewer who
does not read the base language cannot tell it from a translated screen, and the
layout is backwards in a way that puts punctuation, brackets and embedded
numbers on the wrong side. `fill_direction_mismatch` is its own code rather than
a line on `missing_key`, because a team that turned the fill on has already
accepted missing translations — that warning is the one most likely to be
ignored, and this is not the problem it describes.

**The count is messages, not findings.** `missing_key` collapses an entire
untranslated namespace into one diagnostic, so two findings can stand for two
hundred messages and the number of findings would understate the problem by two
orders of magnitude. The tally is taken while the structure is compared, and a
renamed key counts as filled, because the key is still absent under its new name
and codegen substitutes base text for it.

Isolating the interpolated values is the other half of this, and it is a codegen
decision rather than a locale one, so it has a subsection of its own below.

### `bidi_isolation`: two characters, and the measurement that justifies them

A value is whatever somebody typed, so its direction is not the sentence's. The
bidi algorithm resolves the two together, and the result is text that is wrong
on the screen and right in every string comparison — the class of defect this
library exists to move to build time, except that this one cannot be moved
there, because the value does not exist until run time. What *can* be decided at
build time is where the boundaries of the value are, and that is the whole of
the feature: U+2068 FIRST STRONG ISOLATE before the interpolation, U+2069 POP
DIRECTIONAL ISOLATE after it, in the string literal.

**Measured before it was written.** Eight cases were laid out with a
`TextPainter`, with and without the isolates, and the character positions read
back; five changed and three did not. The three that changed for a Latin value
in a Hebrew line, each one the isolated version being the correct one:

| value | without the isolates | with them |
| --- | --- | --- |
| `Ada.` | the stop is laid out on the far side of the name | `Ada.` |
| `3 Ada` | laid out as `Ada 3` | `3 Ada` |
| `-5%` | laid out as `5%-` | `-5%` |

The two that did not change are in the test as well, because a feature's limits
are worth as much as its effect: a parenthesised Latin filename inside a Hebrew
sentence and a parenthesised Hebrew name inside an English one are both already
correct, mirrored brackets included. The other two cases that changed are an
ordering question rather than a repair — two values with a separator between
them read in the sentence's order once they are isolated, and in the values' own
order when they are not.

That is why the test lives in `packages/l10n_plus_flutter/test/`, with a real
text painter, rather than asserting that the generator wrote two code points.
Two code points are not the claim.

**What is isolated, and what is deliberately not.**

* Every placeholder that sits in text, in every locale. Not only the right to
  left ones: an embedded Hebrew name in an English sentence is the same problem
  from the other side, and the generator does not know which values will be
  foreign anyway.
* The plural count as well. `#` is a value whose rendering can carry a sign or a
  percent, which is one of the three measured cases.
* A message that is *nothing but* a placeholder is left alone. There is no text
  in that string for the value to be reordered against, the widget's own
  direction decides the line, and leaving it alone keeps the `String`
  passthrough an allocation free getter.
* A placeholder alone in one span of a *rich* message is isolated, because a
  rich message is one paragraph assembled from several strings and the rest of
  the sentence is in the sibling spans. Same rule, applied to the real boundary
  rather than to the string's.
* A nested choice's rendering is never isolated: it is this locale's own words in
  this locale's own direction, and whatever foreign value sits inside it was
  isolated where it was interpolated.
* On the override path the *values* are isolated, not the override's text. So a
  bundle that reworded the sentence around a value gets the isolates without
  knowing they exist — and a message that is a bare placeholder today is
  isolated there, because an override may put words around it. Nothing about the
  overridable surface changes, so turning the option on does not invalidate a
  bundle anybody has stamped.

**Emitted as `\u{2068}` escapes, not as the characters.** A generated file is
read, reviewed and grepped, and two invisible code points in a literal are two
things a reader cannot see. The braced form also keeps the generated file past
`text_direction_code_point_in_literal`, the lint that exists because a direction
control in source is how a patch is made to read as something it is not — the
generated header already ignores lints, but a reviewer's eye does not.

**Off by default, and said once.** The isolates are invisible, so a test
comparing a rendered message against a literal has to carry them too. That cost
was measured rather than guessed: turning the option on in the Arabic
evaluation application changes 285 lines of its generated file and breaks 9 of
its 20 tests, every one of them a string compared against a literal. It is a
trade the project cannot make on anybody's behalf. So a project with a right to left
locale that interpolates anything gets `bidi_isolation_off` once, naming the
locale, what goes wrong, the option, and `ignore_diagnostics` — silent for a
project with no such locale, for one whose messages interpolate nothing, and for
a select, whose value is a generated enum and never reaches the string.

### Rich text: data in the core, the guarantee in the glue

A link inside a sentence has to be one message, because word order belongs to
the translator. The question was where the Flutter types go, since the runtime
has no dependencies and the base generated file is compiled by a server.

Answer: **the core emits data, the glue emits the guarantee.** A `(rich)` key
yields `List<L10nSpan>` — a text run or a named tag with children, `const` when
the message has no placeholders — and the Flutter glue, which already imports
`package:flutter`, emits a wrapper that takes one builder per tag the message
contains and folds the whole thing into a `TextSpan`. So a forgotten tag is a
compile error, and the pure-Dart file never grows a Flutter import. The span
types are re-exported only in a project that has a rich message, which is why
every existing golden is byte-identical.

**Tags are a layer over the ICU AST, not a sixth node kind.** The rich parser
runs over the `MessageBody` the ICU parser already produced and reads tags out
of its literals. The model keeps the plain parse, so signature inference,
cross-locale validation and the generated doc comments needed no new case, and
a `{amount, number, currency:USD}` inside a tag formats through the existing
code path rather than a second implementation of it.

**The suffix is part of the key**, so every locale writes it and richness
cannot disagree between locales — a mismatch is already `missing_key` or
`renamed_key`, diagnostics that exist and explain themselves. What can still
disagree is the tag *set*, and that is `rich_tag_mismatch`, naming both files.

**A rich plural is refused, not half-supported.** One builder per tag only
type-checks while the tag set is static, and inside plural or select branches it
is not. `rich_unsupported_choice` says to split the message and choose in Dart.
Three of the four new codes are errors for the same reason the rest of the
generator is strict: markup that nearly parses is the kind of thing that reaches
a screen.

### Interchange runs before validation, and edits rather than rewrites

`export`/`import` sit in front of cross-locale validation rather than after it.
The reason is the whole point of the feature: under the default configuration an
incomplete locale is an **error**, and that locale is exactly the one somebody
is exporting for. A command that refuses to run until the translations are
complete would only be useful to a project that does not need it. Parse errors
still stop both commands — a file nobody can read is not a hand-off.

**`import` splices, it does not reserialize.** Each new string is written at its
own leaf's value span, so key order, blank lines, YAML comments, indentation
(step inferred from the file) and line endings (CRLF detected) survive, and the
diff a reviewer reads is the translations and nothing else. Reserializing would
have been a tenth of the code and would have put a thousand-line reformat in
front of every translation drop.

**The dry run is the default.** Silently rewriting a developer's translation
files is the one unforgivable behaviour here, and a dry run with pending changes
exits 0 on purpose: this is a report, not a CI gate. `analyze` is the gate.

**It creates nothing.** A locale with no file, or a key with no file to anchor
it, is a warning rather than a new file: inventing a name, a format and a layout
is the tool deciding how somebody's repository is arranged. It also never
deletes and never reorders, so a key dropped from the hand-off file stays.

The round trip is asserted rather than claimed — export, read back, plan the
import, and the translation files are byte-identical, over JSON, YAML, ARB and a
split layout, in both formats, with a count assertion so that "nothing changed"
cannot pass vacuously. Byte identity alone would pass a tool that silently did
nothing, so two further tests check that every message survives with its text
intact and that the encoder reproduces the literal already in the file.

### Runtime overrides: the text of one branch, and nothing else

The feature is fixing a typo without a release. The naive way to build it ships
an ICU parser and plural rules into the runtime, so that a downloaded
`{count, plural, one{…} other{…}}` can be evaluated — which would duplicate the
one thing this library is actually better at than the field, in the package that
has **no dependencies**, and would mean a Russian override selecting its
category by a second, unverified implementation of CLDR.

So the split is: **the generated code keeps the decisions, the override carries
the words.** The compiled `if` chain picks the plural category exactly as before
and then asks the store for *that branch*; `package:intl` formats every argument
exactly as before and the formatted strings are substituted into `{name}` and
`#`. What arrives over the network is text with holes in it, and the runtime
cost of using it is a token substitution, not a parse.

That also fixes the API surface in place: an override cannot add a key, add or
drop a placeholder, or invent a branch. Those are a release, which is the
honest version of the promise — `rerune`'s shape, and the reason this is safe
to ship at all.

**`setLocale` stays synchronous.** The roadmap predicted for two milestones that
OTA would be the feature that made it async. It is not: fetching happens in the
application's own code, before the install, and the install itself is a map
assignment. The prediction was wrong because it assumed the library would do the
fetching, and the library has no business doing it — HTTP, caching,
authentication and retry are the application's, and a localization package with
`http` in its dependency graph is the thing we are trying not to be.

**Off by default, and nothing is emitted when it is off.** With
`runtime_overrides: false` every golden is byte for byte what it was, which the
existing golden tests assert rather than take on trust. Turned on, consulting
the store on the cheapest possible message read — a `const` getter, nothing
installed — costs 1.8 ns, one `isEmpty` on a static map; with a bundle installed
that does not carry the key, 28.5 ns for two lookups. Measured in
`example/benchmark/`, not guessed.

**The global store is a considered exception.** Milestone 27 defers an ambient
`current` accessor over global mutable state, and the objection there is real: a
widget reading an ambient value creates no dependency, renders once, and then
keeps the old language after a switch. It does not apply here, because
installing *notifies* — `L10nController` subscribes to the store itself, so
every reader repaints whoever installed — and because overrides are a property
of the application rather than of a subtree, so there is no second copy to
disagree with. The hazard that
does apply is the ordinary one: a store installed by one test is still installed
in the next, which `clear()` in a `tearDown` answers.

### `check-overrides` is what keeps the feature honest

OTA moves a class of error back to run time, in a library whose whole argument
is that those errors belong at build time. Left there, it would quietly undo the
thing being sold. So a bundle is validated against the project before it ships,
and the check that matters is one nobody else in the field can make: **a branch
name is checked against the plural categories of that particular choice**, read
from the same CLDR table the conditions were compiled from. So `two` is a
mistake in an English cardinal plural and correct in an English ordinal; `one`
is right for a Russian cardinal and wrong for a Russian ordinal, which has only
`other`. Probe 19 replays it.

Twelve codes, all errors, and all of them failures a bundle can be fixed for
before anyone sees it: a key the project does not define (with the nearest key offered),
a placeholder the message does not take, `#` where there is no count, text that
contains ICU — which means the author expected rules that will be ignored — a
rich message, which is structure rather than text, and the shape confusions in
both directions (branches supplied for a message with one form, and one string
supplied for a message that branches).

At run time, by contrast, nothing throws: an unknown token is left standing in
the string. A wrong override must not crash an application that is already in
somebody's hands, and the check is what makes that a safe default rather than a
shrug.

### The fingerprint: the one thing the bundle cannot be asked about

Every answer above is an answer about the project *as it stands*, and a bundle
outlives a build. Branches of a nested choice are addressed by position —
`0/one` is the `one` branch of a message's first nested choice, `{#0}` is that
choice's rendering in the text around it — so a release that puts another plural
ahead of it renumbers everything after it. Every name in the old bundle still
exists, so every check above still passes, and the words of one choice are now
the words of another. Measured on a real project, the same bundle before and
after such a release:

```
compiled:  You have 1 wallet with 1 card linked
installed: You have 1 saved card with 1 card linked
```

Nothing in the bundle can say which build it meant, so the build says it.
`check-overrides --stamp` writes the surface it checked the bundle against into
the bundle as `@@fingerprint`; the generated `AppLocale.ru.installOverrides`
carries this build's own as a constant and throws `L10nOverrideMismatch` for any
other, installing nothing. The application then renders what it compiled, which
is the right text for the build that is running — the same "a wrong override
must not make things worse" rule as the standing `{token}`.

**What it covers is what can change meaning, not what can change.** The keys,
each message's slots, the tokens each slot substitutes, and what each choice
selects on. Not the text: a reword is the release an override exists to avoid
waiting for, and invalidating every bundle over one would defeat the feature.
Not the CLDR categories of the language either, though the branch check consults
them — a CLDR upgrade that leaves the emitted branches alone leaves every bundle
correct, and a false refusal costs an application its live text.

Nothing in it depends on order: messages are sorted by key and slots by branch
name, so moving a message or reordering a plural's branches invalidates nothing.
The one order that *is* captured is the numbering of the nested choices, which
lives inside the branch names and the `#n` tokens, because that is the case this
exists for. Two nested choices of the same categories have the same slot names
in either order, which is why the canonical form also records the argument each
choice selects on — swap `{a, plural, …}` and `{b, plural, …}` in one message
and nothing else in the surface moves.

**Coarse on purpose.** One value per locale, so a release that adds a message
invalidates that locale's bundles although their entries are all still valid.
The alternative is a per-message hash, which is exact and puts a hash beside
every string in a file a translator's tooling has to carry; the coarse version
costs one `--stamp` in a release that had to re-check its bundles anyway. The
locale tag is inside the value, so a bundle cannot be installed for a locale it
was not checked against — `en` and `en_GB` usually do have the same messages.

**It identifies, it does not authenticate.** FNV-1a over the canonical form, 64
bits, 16 hex digits, hand rolled in 20 lines. The threat is drift between a
bundle and a build, not forgery: anybody who can replace the bundle an
application downloads can replace the fingerprint inside it, and the integrity
of that download is TLS's job. A cryptographic digest truncated to the same 16
digits would say exactly as much and cost a dependency.

**`--stamp` is the check signing what it checked**, not a convenience for typing
hashes. It writes only when every other check passes, and it edits the file in
place — the value's own span when there is one, otherwise an entry inserted
after the brace, laid out the way the file lays out its own members — for the
reason `import` edits instead of rewriting: the file belongs to whoever wrote
it. Probe 19 asks for a stamp on a bundle with a bad branch and does not get
one; probe 20 stamps a good bundle, moves a choice, and is refused.

**A bundle that states no fingerprint is still installed.** The check refuses
one — `missing_override_fingerprint`, with the line to paste — because that is
where this project refuses things, and because a stamp is one flag away. The
runtime does not, because its job is never to make a running application worse,
and because `install` is also what a test and an in-Dart assembly call, where
there is no build to speak of. Build time decides what may ship; run time
decides what is safe to do with what shipped.

### A directory is the unit a release is assembled in

`check-overrides --from` takes a bundle or a directory of them, and the second
is not a convenience loop over the first. Three of its answers do not exist at
the scale of one file, and a twelve language rollout checked a file at a time
can pass twelve times and still be wrong as a set.

**A locale with no bundle.** Reported by the command rather than as a
diagnostic, because it is not a fault: a locale nobody wrote a bundle for keeps
the text it compiled, which is correct. It is also the omission a rollout
actually makes, and it is invisible while you are naming files one at a time.

**Two bundles claiming one locale.** `duplicate_override_locale`, the one new
code. An `en.json` beside an `overrides_en.json` — both valid, both passing
every per-file check, and which of them the application installs decided by
whatever serves them rather than by anything here. The locale of a bundle comes
from `@@locale` or from its file name, so the clash can be between two
declarations, two names, or one of each; all three are the same mistake. The
duplicate is still checked for everything else, because reporting as much as
possible is as true of six files as of one.

**Whether the set may be signed.** `--stamp` on a directory validates every
bundle before it writes any. A release in which some bundles carry a fingerprint
and some do not is the worst available state — nothing on disk says which of
them was checked — so one wrong branch in Russian leaves all twelve unstamped,
and the report says that it did. The one file case runs the same two passes with
one entry, so the two forms cannot drift apart.

Selection is every `.json` directly in the directory, sorted, and nothing below
it: a release of bundles is flat, and recursing would read whatever else a
repository keeps in JSON. A `.json` that is not a bundle is an error naming the
file rather than a silent skip, which is what makes pointing `--from` at the
wrong directory a failure instead of a pass over nothing.

One report at that scale needed a fix nothing else had asked for:
`unknown_override_locale` pointed at the `@@locale` span, which is `null` for a
bundle named after its locale — the normal shape in a directory of them. With
one file you knew which file you had named; with twelve, a report that cannot
say is a hunt. It now falls back to the whole object, so the file is always in
the span.

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

What the option does **not** excuse: a translated key whose arguments disagree
with the base (`missing_placeholder` and friends), or a missing base locale.
Those stay errors, because neither can be filled in from anywhere.

**The mirror case has its own option.** `extra_key` — a key another locale has
and the base does not — was an error with no way out, and that is right for a
finished project and wrong for a team on a TMS: a key deleted from the base
locale keeps arriving from the translators for days, and every language has to
catch up before anyone can build.

`extra_keys: warn` reports it and leaves the key out of generation. The output
is byte for byte what deleting the key by hand would produce, which is the
property that makes the option safe: the base locale still defines the API
exactly, and the setting changes what is reported rather than what is
generated. That falls out of the design rather than being arranged — the model
is built by walking the *base* locale's tree, so a key no base locale key
matches was never going to be emitted.

Two smaller decisions:

* **an extra group is one diagnostic, with a count.** A namespace dropped from
  the base locale is one decision, and "wallet is not in the base locale (200
  keys)" reads better than two hundred lines that each say a fifth of it;
* **the default stays `error`, including when the option cannot be read.** A
  value the generator does not understand gets `invalid_config` and keeps the
  strict behaviour. An unreadable option must never be the reason a build got
  looser than the project asked for.

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
  folding, not the access. `identical` on two accessors is a sample, though,
  and "no allocation" is a claim about all of them:
  `const_graph_test.dart` reads the emitted source and fails unless *every*
  namespace accessor returns a `const` instance and every implementation
  class has a `const` constructor. Dropping the `const` the emitter writes
  makes it name all twelve accessors that would start allocating.
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

### The Flutter edge, measured

`example/test/flutter_cost_test.dart`, run by `flutter test`. That is not a
profile mode device: no vsync, JIT, and whatever else the machine is doing.
The absolutes are an upper bound; the split between them is the point.

| | |
| --- | --- |
| `AppLocalizations.forLocale(...)` then three getters | 6 ns |
| `context.l10n` then the same three getters | 44 ns |
| `AppLocalizations.of(L10nLocale.parse(tag))` | 394 ns |

`context.l10n` costs about eight times the direct call, and the difference is
`dependOnInheritedWidgetOfExactType` — Flutter's, not this library's. Reading
a translation through a `BuildContext` is still an order of magnitude cheaper
than resolving a locale tag, which parses a string.

Switching locale over a tree of 200 widgets, 100 of which read `context.l10n`:
7.4 ms median of nine switches, 14.2 ms for the first because it compiles the
Russian path. That is 74 µs per rebuilt widget, which is a `flutter test`
number for Flutter's rebuild pipeline and says nothing about this package —
what the package contributes is one `notifyListeners`.

What is worth guarding, and is asserted rather than printed: **exactly the
hundred widgets that read the locale rebuild, and the other hundred never do**
— on every switch, not only the first. A scope that rebuilt its whole subtree
would still pass a timing threshold on a fast machine and would be the real
defect.

### A warning nobody can turn off is a warning nobody reads

`missing_plural_category` is true and useful. At three thousand keys in ten
locales it is also two thousand identical lines about a decision the team made
months ago, and a report that long is not read — which costs the warnings that
*were* worth reading.

`ignore_diagnostics` takes a list of codes. Three constraints shape it:

* **only warnings are ever dropped.** The filter lives in `DiagnosticCollector`
  and checks the severity of the diagnostic in hand, not a static property of
  the code. So `missing_key`, which is a warning under
  `fill_missing_from_base` and an error without it, can be listed and only its
  warning form disappears. An error stops generation; hiding it would hide the
  reason the build failed.
* **an entry that silences nothing is reported.** A misspelled code and a code
  that is always an error both get `invalid_config`, because the failure being
  prevented is a project believing a warning is off when it is not. That needs
  a list of every code the generator can emit, which is `DiagnosticCodes` — and
  a hand written list of that kind drifts, so a test scrapes the sources and
  fails when a code is not registered. It found one the day it was written.
* **the count is always printed.** `1842 ignored` at the end of the report. A
  silenced warning nobody remembers silencing is a worse problem than the
  warning was.

The list is armed *after* the configuration has been parsed, so the complaints
about the configuration itself cannot be silenced by it.

### `=N` can cover a whole category

A `gen_l10n` bundle writes `{count, plural, =0{none} =1{one} other{# items}}`,
and the validator reported that English `one` was missing. It was not: English
defines `one` as `i = 1 and v = 0`, true of 1 and of nothing else, so the `=1`
branch renders every value the category could ever select. Every ARB bundle
imported from `gen_l10n` met a warning with no fix under it.

A category is now covered when the language defines it as a **single exact
value** and an `=N` branch matches that value. The value is read off the
generated condition — `@n == N`, or `@i == N && @v == 0` — rather than from a
hand written list, because a hand written list would drift from the conditions
and the conditions are what actually run.

Deliberately not general. Nothing tries to prove that a set of literals covers
a range: Arabic `few` is `n % 100 = 3..10`, which no list of `=N` closes, and a
prover that got it wrong would silence a real warning. Russian `one` also takes
21 and 31, so `=1` covers nothing there and the warning stays — which is the
case the check has to keep getting right.

`offset:` disables it entirely. ICU matches `=N` against the original value and
selects the category from the adjusted one, so the two are about different
numbers and neither can cover the other.

### Date symbols: the error names the call

`DateFormat.yMMMd('ru')` throws when it is **built**, not when it formats. The
generated formatters are lazily initialized top level finals, so the failure
lands on the first read of one, carrying intl's own message: "Locale data has
not been initialized, call initializeDateFormatting(<locale>)". True, and it
cannot know that this generator emitted `initializeAppLocalizationsFormatting`
for exactly this.

Loading them lazily was considered and does not work: `initializeDateFormatting`
is asynchronous and a field initializer is not, so there is nowhere to await.
An `assert` does not help either — the throw happens inside the initializer,
before anything the generated code could assert on.

What is left is the error. Every `DateFormat` is built through a small
generated helper that catches, and rethrows naming the call:

```dart
final DateFormat _ruDateYMMMd = _dateFormat('ru', () => DateFormat.yMMMd('ru'));
```

```
Bad state: Date symbols for "ru" are not loaded.
Call `await initializeAppLocalizationsFormatting()` once during start up,
before reading a date formatted message.
Underlying error: LocaleDataException: ...
```

It catches `Exception` rather than `LocaleDataException`, which `intl` does not
export, and carries the original along rather than swallowing it. The helper is
emitted only when something formats a date, and with `file_per_locale` it is
declared once in the shared file — the parts are one library with it.

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

PO/XLIFF/XML/TOML, a vendor API (Crowdin, Lokalise, POEditor), an IDE plugin, a
hot-reload daemon, a translation editor, dynamic string-keyed lookup, and
anything that fetches over a network — the application owns the HTTP, the cache
and the credentials, and this library owns no dependency it could spend on
them. See `docs/roadmap.md` for the order the rest is expected in.

Runtime overrides and ARB/CSV interchange used to be on this list and are now
in; `L10nOverrides` and `export`/`import` are described above.
