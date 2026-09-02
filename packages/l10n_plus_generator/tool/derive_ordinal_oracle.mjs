// Dumps CLDR ordinal plural categories from ICU, for test/data/cldr_ordinals.json.
//
// `package:intl` ships cardinal rules only, so the differential test for
// `selectordinal` has no oracle inside the Dart ecosystem. ICU has one, and
// `Intl.PluralRules(locale, {type: 'ordinal'})` is it. The answers are
// vendored rather than queried at test time so that the suite needs nothing
// but Dart; this script exists so the vendored file can be regenerated and
// argued with.
//
//   node tool/derive_ordinal_oracle.mjs <lang> <lang> ... > test/data/cldr_ordinals.json
//
// The language list is the generator's own table; `tool/ordinal_oracle.sh`
// passes it in.

const LEGEND = {zero: 'z', one: 'o', two: 't', few: 'f', many: 'm', other: 'x'};

/** Integers up to 1200 catch every modulus CLDR ordinals use, 800 included. */
const samples = [
  ...Array.from({length: 1201}, (_, i) => i),
  2000, 3000, 8000, 10000, 10001, 100000, 1000000, 1000001,
  0.5, 1.5, 2.5, 1.1, 0.1,
];

const languages = process.argv.slice(2);
if (languages.length === 0) {
  console.error('usage: node derive_ordinal_oracle.mjs <lang>...');
  process.exit(64);
}

const locales = {};
const categories = {};
for (const language of languages) {
  const rules = new Intl.PluralRules(language, {type: 'ordinal'});
  const resolved = rules.resolvedOptions();
  // ICU answers for *something* whatever you ask; an unknown tag comes back
  // as the runtime default. Refuse rather than vendor en-US under its name.
  if (new Intl.Locale(resolved.locale).language !== language) {
    console.error(
      `ICU has no ordinal data for "${language}": it resolved to ` +
      `"${resolved.locale}". Remove it or vendor its rules another way.`,
    );
    process.exit(1);
  }
  locales[language] = samples.map((n) => LEGEND[rules.select(n)]).join('');
  categories[language] = resolved.pluralCategories.slice().sort();
}

process.stdout.write(JSON.stringify({
  source: `Intl.PluralRules {type:'ordinal'}, ICU ${process.versions.icu}, ` +
      `CLDR ${process.versions.cldr}, Node ${process.versions.node}`,
  regenerate: 'tool/ordinal_oracle.sh',
  legend: Object.fromEntries(
      Object.entries(LEGEND).map(([name, code]) => [code, name])),
  samples,
  categories,
  locales,
}, null, 2) + '\n');
