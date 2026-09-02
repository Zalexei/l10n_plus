#!/bin/zsh
# Regenerates test/data/cldr_ordinals.json from ICU, for every language the
# cardinal table knows. Needs Node with full ICU; nothing in the test suite
# does, because the answers are vendored.
#
#   tool/ordinal_oracle.sh
set -eu
cd "${0:a:h}/.."
langs=$(dart run tool/list_languages.dart)
node tool/derive_ordinal_oracle.mjs ${=langs} > test/data/cldr_ordinals.json
print -r -- "wrote test/data/cldr_ordinals.json for $(print -r -- $langs | wc -w | tr -d ' ') languages"
