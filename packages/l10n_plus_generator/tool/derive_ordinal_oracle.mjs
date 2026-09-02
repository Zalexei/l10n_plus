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
const aliased = {};
for (const language of languages) {
  const rules = new Intl.PluralRules(language, {type: 'ordinal'});
  const resolved = rules.resolvedOptions();
  // ICU answers for *something* whatever you ask; an unknown tag comes back
  // as the runtime default. Vendoring en-US under another name would be an
  // oracle that agrees with anything, so those are recorded and skipped
  // rather than written out.
  //
  // The case that actually happens is a deprecated code CLDR still publishes
  // and ICU folds away: `mo` is Moldovan, and ICU resolves it to `ro`. The
  // rules in the table are right — they are CLDR's own — but ICU cannot give
  // a second opinion on a name it does not keep, so this file says so
  // instead of pretending to cover it.
  const resolvedLanguage = new Intl.Locale(resolved.locale).language;
  if (resolvedLanguage !== language) {
    aliased[language] = resolvedLanguage;
    continue;
  }
  locales[language] = samples.map((n) => LEGEND[rules.select(n)]).join('');
  categories[language] = resolved.pluralCategories.slice().sort();
}
if (Object.keys(aliased).length > 0) {
  console.error(
    `ICU folds ${Object.keys(aliased).length} language(s) onto another and ` +
    `cannot answer for them: ` +
    Object.entries(aliased).map(([a, b]) => `${a}->${b}`).join(', '),
  );
}

process.stdout.write(JSON.stringify({
  source: `Intl.PluralRules {type:'ordinal'}, ICU ${process.versions.icu}, ` +
      `CLDR ${process.versions.cldr}, Node ${process.versions.node}`,
  regenerate: 'tool/ordinal_oracle.sh',
  legend: Object.fromEntries(
      Object.entries(LEGEND).map(([name, code]) => [code, name])),
  samples,
  aliased,
  categories,
  locales,
}, null, 2) + '\n');
