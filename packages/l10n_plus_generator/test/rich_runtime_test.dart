@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/rich/app_localizations.g.dart';

/// Runs the rich text golden instead of only reading it.
///
/// The golden test proves the file was written and `dart analyze` proves it
/// type checks. Neither proves the span tree is the right shape: a tag whose
/// children were dropped, a text run split in two, or a `const` the emitter
/// stopped writing all compile perfectly. This is the same file, executed.
void main() {
  final en = AppLocalizations.forLocale(AppLocale.en);
  final ru = AppLocalizations.forLocale(AppLocale.ru);

  test('a message with no placeholder is one canonical constant', () {
    // `const` is the claim the generated getter makes. Dart canonicalizes
    // const values, so identity is the proof that nothing is allocated per
    // read — the same assertion the namespace accessors get.
    expect(identical(en.legal.terms, en.legal.terms), isTrue);
    expect(en.legal.terms, same(const AppLocalizationsEn().legal.terms));
  });

  test('text, tag, text — in order, with the tag holding its children', () {
    expect(en.legal.terms, [
      const L10nTextSpan('Read the '),
      const L10nTagSpan('link', [L10nTextSpan('terms of service')]),
      const L10nTextSpan(' to continue'),
    ]);
  });

  test('each locale keeps its own words and the same tags', () {
    expect(ru.legal.terms, [
      const L10nTextSpan('Чтобы продолжить, прочитайте '),
      const L10nTagSpan('link', [L10nTextSpan('условия обслуживания')]),
    ]);
    expect(
      ru.legal.terms.whereType<L10nTagSpan>().map((span) => span.tag),
      en.legal.terms.whereType<L10nTagSpan>().map((span) => span.tag),
    );
  });

  test('a placeholder is interpolated into the span that wraps it', () {
    final spans = en.legal.greeting(name: 'Ada', amount: 12.5);
    expect(spans[0], const L10nTextSpan('Hi '));
    expect(
      spans[1],
      const L10nTagSpan('bold', [
        L10nTagSpan('italic', [L10nTextSpan('Ada')]),
      ]),
    );
    expect(spans[2], const L10nTextSpan(', you owe '));
  });

  test('a format declared inside a tag really formats', () {
    // Reading the source shows the formatter call; running it shows that the
    // currency reached the span, in the locale being rendered.
    expect(
      en.legal.greeting(name: 'Ada', amount: 12.5).last,
      const L10nTagSpan('bold', [L10nTextSpan('USD12.50')]),
    );
    expect(
      L10nSpan.plainText(ru.legal.greeting(name: 'Ада', amount: 12.5)),
      // A non breaking space before the code, which is what `ru` uses.
      'Привет, Ада! Вы должны 12,50 USD',
    );
  });

  test('plainText is the sentence without its markup', () {
    expect(
      L10nSpan.plainText(en.legal.terms),
      'Read the terms of service to continue',
    );
    expect(L10nSpan.plainText(en.banner), 'Welcome to l10n_plus');
  });

  test('a plain message in the same project is still a String', () {
    expect(en.legal.notice, 'Angle brackets such as <b> stay literal here');
  });
}
