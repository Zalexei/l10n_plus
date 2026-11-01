#!/bin/zsh
# Replays every deliberate mistake made during the evaluation and prints the
# diagnostic each one produced. Run from evaluation/probes:
#
#   ./probe.sh            all probes
#   ./probe.sh 12         one probe
#
# The workspace is a real project with path overrides on the local packages.
set -u
cd "${0:a:h}/workspace" || exit 1
only=${1:-}

reset() { rm -rf translations lib; mkdir -p translations; }
config() { cat > l10n_plus.yaml; }
base_config() {
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
flutter:
  enabled: false
EOF
}
gen() { dart run l10n_plus_generator "${1:-generate}" 2>&1; echo "exit=$?"; }
probe() {
  [[ -n $only && $only != $1 ]] && return 1
  print -r -- ""
  print -r -- "######## $1. $2 ########"
  reset; base_config
  return 0
}

probe 1 "ICU: unclosed brace" && {
  print '{"a": "Hello {name"}' > translations/en.json; gen; }

probe 2 "ICU: plural without an other branch" && {
  print '{"a": "{n, plural, one{# thing}}"}' > translations/en.json; gen; }

probe 3 "ICU: unknown number style" && {
  print '{"a": "{n, number, moneyish}"}' > translations/en.json; gen; }

probe 4 "arguments disagree between locales" && {
  print '{"a": "Hi {name}"}' > translations/en.json
  print '{"a": "Привет, {userName}"}' > translations/ru.json; gen; }

probe 5 "plural in one locale, select in another" && {
  print '{"a": "{n, plural, one{# x} other{# xs}}"}' > translations/en.json
  print '{"a": "{n, select, a{A} other{B}}"}' > translations/ru.json; gen; }

probe 6 "a key here, a group there" && {
  print '{"wallet": "Wallet"}' > translations/en.json
  print '{"wallet": {"a": "A"}}' > translations/ru.json; gen; }

probe 7 "a plain number where the base has a plural" && {
  print '{"a": "{n, plural, one{# x} other{# xs}}"}' > translations/en.json
  print '{"a": "{n, number} штук"}' > translations/ru.json; gen; }

probe 8 "forgot package:intl" && {
  print '{"a": "Total {n, number}"}' > translations/en.json; gen; }

probe 9 "a file whose name is not a locale" && {
  print '{"a": "A"}' > translations/en.json
  print '{"a": "B"}' > translations/strings.json; gen; }

probe 10 "@@locale disagrees with the path" && {
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
file_pattern: "app_{locale}"
flutter:
  enabled: false
EOF
  print '{"@@locale": "en", "a": "A"}' > translations/app_en.arb
  print '{"@@locale": "de", "a": "B"}' > translations/app_ru.arb; gen; }

probe 11 "no file for the base locale" && {
  print '{"a": "A"}' > translations/ru.json
  print '{"a": "B"}' > translations/de.json; gen; }

probe 12 "two files of one locale define the same key" && {
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
file_pattern: "{namespace}_{locale}"
flutter:
  enabled: false
EOF
  print '{"title": "A"}' > translations/auth_en.json
  print '{"title": "B"}' > translations/auth_en.yaml; gen; }

probe 13 "select branches named after what an enum already has" && {
  print '{"a": "{s, select, values{V} index{I} hashCode{H} other{O}}"}' \
    > translations/en.json
  gen; print -r -- "-- and the result analyzes:"; dart analyze lib 2>&1 | tail -2; }

probe 14 "keys that collide once normalized" && {
  print '{"appLocale": {"a": "A"}, "user_name": "x", "userName": "y"}' \
    > translations/en.json; gen; }

probe 15 "a typo and a bad value in the config" && {
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
file_per_local: true
format_plural_numbers: "yes please"
flutter:
  enabled: false
EOF
  print '{"a": "A"}' > translations/en.json
  gen; print -r -- "-- analyze, the CI command:"; gen analyze; }

probe 16 "a language with no CLDR rules in the table" && {
  # `cy` used to land here; it is in the table now, so this needs a language
  # CLDR really has no rules for.
  print '{"a": "{n, plural, one{# item} other{# items}}"}' > translations/en.json
  print '{"a": "{n, plural, other{# eitem}}"}' > translations/tlh.json; gen; }

probe 17 "a number format on a select argument" && {
  print '{"@@locale": "en", "g": "{g, select, a{A} other{B}}", "@g": {"placeholders": {"g": {"type": "String", "format": "currency"}}}}' \
    > translations/en.arb; gen; }

probe 18 "a currency on a plural count, which is honoured" && {
  print '{"@@locale": "en", "cards": "{count, plural, one{# card} other{# cards}}", "@cards": {"placeholders": {"count": {"type": "num", "format": "currency"}}}}' \
    > translations/en.arb
  gen
  print -r -- "-- and the count decides the branch on what it displays:"
  sed -n '/String cards(.*) {/,/^  }/p' lib/l10n/app_localizations.g.dart; }

probe 19 "an override branch the locale's plural rules cannot select" && {
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
runtime_overrides: true
flutter:
  enabled: false
EOF
  print '{"items": "{n, plural, one{# item} other{# items}}"}' > translations/en.json
  print '{"items": "{n, plural, one{# предмет} few{# предмета} many{# предметов} other{# предмета}}"}' \
    > translations/ru.json
  gen > /dev/null
  print '{"@@locale": "ru", "items": {"one": "# штука", "two": "# штуки", "other": "# штук"}}' \
    > overrides_ru.json
  dart run l10n_plus_generator check-overrides --from=overrides_ru.json --stamp 2>&1
  print -r -- "exit=$?"
  # --stamp was asked for and refused: a fingerprint says this bundle was
  # validated against this build, and this one was not.
  print -r -- "bundle after: $(cat overrides_ru.json)"
  rm -f overrides_ru.json; }

probe 20 "an override stamped for a build whose nested choices have moved" && {
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
runtime_overrides: true
flutter:
  enabled: false
EOF
  print '{"m": "You have {a, plural, one{# card} other{# cards}}"}' > translations/en.json
  gen > /dev/null
  print '{"@@locale": "en", "m": {"0/one": "# card saved", "0/other": "# cards saved"}}' \
    > overrides_en.json
  dart run l10n_plus_generator check-overrides --from=overrides_en.json --stamp 2>&1
  # A release puts another plural ahead of the one the bundle addresses. Every
  # branch name in the bundle still exists; "0/one" is now the other choice's.
  print '{"m": "You have {b, plural, one{# bag} other{# bags}} and {a, plural, one{# card} other{# cards}}"}' \
    > translations/en.json
  gen > /dev/null
  dart run l10n_plus_generator check-overrides --from=overrides_en.json 2>&1
  print -r -- "exit=$?"
  rm -f overrides_en.json; }

probe 21 "a right to left locale with nothing isolating its values" && {
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: he
fallback_locale: he
flutter:
  enabled: false
EOF
  print -r -- '{"greeting": "שלום {name} בוקר"}' > translations/he.json
  gen
  print -r -- "-- and with bidi_isolation: true, the value is wrapped:"
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: he
fallback_locale: he
bidi_isolation: true
flutter:
  enabled: false
EOF
  gen > /dev/null
  grep -n 'u{2068}' lib/l10n/app_localizations.g.dart; }

probe 22 "a release of bundles with two of them claiming one locale" && {
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
runtime_overrides: true
flutter:
  enabled: false
EOF
  print '{"title": "Log in", "items": "{n, plural, one{# item} other{# items}}"}' > translations/en.json
  print '{"title": "Войти", "items": "{n, plural, one{# товар} few{# товара} many{# товаров} other{# товара}}"}' > translations/ru.json
  print '{"title": "Anmelden", "items": "{n, plural, one{# Artikel} other{# Artikel}}"}' > translations/de.json
  gen > /dev/null
  mkdir -p overrides
  # Neither of the two en files declares "@@locale", so both claim en by name
  # alone -- which is how an old bundle survives beside a new one.
  print '{"title": "Sign in"}' > overrides/en.json
  print '{"title": "Log in again"}' > overrides/overrides_en.json
  print '{"title": "Вход"}' > overrides/ru.json
  dart run l10n_plus_generator check-overrides --from=overrides --stamp 2>&1
  print -r -- "exit=$?"
  print -r -- "fingerprints written: $(grep -l fingerprint overrides/*.json 2>/dev/null | wc -l | tr -d ' ')"
  print -r -- "-- and with the stale file gone, the release signs as a whole:"
  rm overrides/overrides_en.json
  dart run l10n_plus_generator check-overrides --from=overrides --stamp 2>&1
  rm -rf overrides; }

probe 23 "a ring of linked messages, and a link to a key nothing defines" && {
  print '{"brand": "Acme", "a": "see @:b", "b": "and @:a", "c": "from @:brnd"}' \
    > translations/en.json
  gen
  print -r -- "-- and with the ring broken, the links resolve to nothing at run time:"
  print '{"brand": "Acme", "a": "see @:brand", "b": "and @:a", "c": "from @:brand"}' \
    > translations/en.json
  gen > /dev/null
  grep -n "get a =>\|get b =>\|get c =>" lib/l10n/app_localizations.g.dart; }

probe 24 "a link that lends its parameters, and one locale forgetting them" && {
  print '{"greet": "Hello {name}", "items": "{n, plural, one{# item} other{# items}}", "hello": "@:greet, you have @:items"}' \
    > translations/en.json
  print '{"greet": "Привет, {name}", "items": "{n, plural, one{# товар} few{# товара} many{# товаров} other{# товара}}", "hello": "Привет! Товаров нет"}' \
    > translations/ru.json
  gen
  print -r -- "-- and with Russian taking both, the signature is one line in each locale:"
  print '{"greet": "Привет, {name}", "items": "{n, plural, one{# товар} few{# товара} many{# товаров} other{# товара}}", "hello": "@:greet, у вас @:items"}' \
    > translations/ru.json
  gen > /dev/null
  grep -n "String hello" lib/l10n/app_localizations.g.dart; }

probe 25 "deferred locales asked for without the layout that allows them" && {
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
deferred_locales: true
flutter:
  enabled: false
EOF
  print '{"title": "Log in"}' > translations/en.json
  gen
  print -r -- "-- and with the layout key added, the locales become libraries:"
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
file_per_locale: true
deferred_locales: true
flutter:
  enabled: false
EOF
  print '{"title": "Войти"}' > translations/ru.json
  gen > /dev/null
  grep -n "^import 'app_localizations" lib/l10n/app_localizations.g.dart
  print -r -- "-- which is the only line that decides whether a chunk exists:"
  grep -c 'part ' lib/l10n/app_localizations.g.dart; }

probe 26 "a namespace addressed by key whose messages cannot be" && {
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
dynamic_keys: [errors, warnings]
flutter:
  enabled: false
EOF
  print '{"errors": {"offline": "You are offline", "declined": "Card {last4} declined"}}' \
    > translations/en.json
  gen
  print -r -- "-- with the parameterised message moved out, a string becomes a key:"
  print '{"errors": {"offline": "You are offline", "payment": {"declined": "Declined"}}, "warnings": {"slow": "This is taking a while"}}' \
    > translations/en.json
  config <<'EOF'
input_directory: translations
output_directory: lib/l10n
base_locale: en
fallback_locale: en
dynamic_keys: [errors, warnings]
flutter:
  enabled: false
EOF
  gen > /dev/null
  grep -n "^enum ErrorsKey\|^enum WarningsKey\|('payment.declined')\|String operator" lib/l10n/app_localizations.g.dart; }

probe 27 "a list and a map whose elements cannot be either" && {
  print '{"steps": ["Create an account", "Add a card {last4}"], "c(map)": {"a(rich)": "See <b>this</b>"}}' \
    > translations/en.json
  gen
  print -r -- "-- with both fixed, each becomes one const accessor:"
  print '{"steps": ["Create an account", "Add a card"], "countries(map)": {"fr": "France", "de": "Germany"}}' \
    > translations/en.json
  print '{"steps": ["Создайте аккаунт", "Добавьте карту"], "countries(map)": {"fr": "Франция", "de": "Германия"}}' \
    > translations/ru.json
  gen > /dev/null
  grep -n 'get steps =>\|get countries =>' lib/l10n/app_localizations.g.dart
  print -r -- "-- and a list one locale is short of is the missing key it already was:"
  print '{"steps": ["Создайте аккаунт"], "countries(map)": {"fr": "Франция", "de": "Германия"}}' \
    > translations/ru.json
  gen; }

reset; base_config
