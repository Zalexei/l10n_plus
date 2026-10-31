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
  dart run l10n_plus_generator check-overrides --from=overrides_ru.json 2>&1
  print -r -- "exit=$?"
  rm -f overrides_ru.json; }

reset
