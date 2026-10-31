import 'package:l10n_plus/l10n_plus.dart';
import 'package:test/test.dart';

void main() {
  group('L10nLocale.tryParse', () {
    test('canonicalizes case and separators', () {
      expect(L10nLocale.tryParse('EN'), const L10nLocale('en'));
      expect(
        L10nLocale.tryParse('pt-br'),
        const L10nLocale('pt', country: 'BR'),
      );
      expect(
        L10nLocale.tryParse('zh_hant_tw'),
        const L10nLocale('zh', script: 'Hant', country: 'TW'),
      );
    });

    test('rejects malformed tags', () {
      expect(L10nLocale.tryParse(''), isNull);
      expect(L10nLocale.tryParse('e'), isNull);
      expect(L10nLocale.tryParse('en_US_GB'), isNull);
      expect(L10nLocale.tryParse('en-US-extra-more'), isNull);
      expect(L10nLocale.tryParse('1234'), isNull);
      // Ordinary words must not be mistaken for language subtags.
      expect(L10nLocale.tryParse('readme'), isNull);
    });

    test('parse throws on malformed tags', () {
      expect(() => L10nLocale.parse('!!'), throwsFormatException);
    });
  });

  test('renders both tag styles', () {
    const locale = L10nLocale('pt', country: 'BR');
    expect(locale.toLanguageTag(), 'pt-BR');
    expect(locale.toFileTag(), 'pt_BR');
  });

  test('lineage goes from most to least specific', () {
    expect(
      const L10nLocale('zh', script: 'Hant', country: 'TW').lineage,
      const [
        L10nLocale('zh', script: 'Hant', country: 'TW'),
        L10nLocale('zh', script: 'Hant'),
        L10nLocale('zh'),
      ],
    );
    expect(const L10nLocale('en').lineage, const [L10nLocale('en')]);
  });

  group('isRightToLeft', () {
    test('is true for the right-to-left languages', () {
      for (final language in [
        'ar',
        'fa',
        'he',
        'ur',
        'ps',
        'sd',
        'ug',
        'yi',
        'ckb',
        'dv',
        'nqo',
        'syr',
      ]) {
        expect(
          L10nLocale(language).isRightToLeft,
          isTrue,
          reason: '$language is written right to left',
        );
      }
    });

    test('is false for the left-to-right ones', () {
      for (final language in [
        'en',
        'ru',
        'zh',
        'ja',
        'hi',
        'th',
        'am',
        // Kurmanji Kurdish is Latin script; only Central Kurdish is Arabic,
        // and assuming otherwise is the usual mistake.
        'ku',
        // Maltese is Semitic and Latin-scripted.
        'mt',
      ]) {
        expect(
          L10nLocale(language).isRightToLeft,
          isFalse,
          reason: '$language is written left to right',
        );
      }
    });

    test('the region never changes the answer', () {
      expect(const L10nLocale('ar', country: 'EG').isRightToLeft, isTrue);
      expect(const L10nLocale('he', country: 'IL').isRightToLeft, isTrue);
      expect(const L10nLocale('en', country: 'IL').isRightToLeft, isFalse);
      expect(const L10nLocale('fa', country: 'AF').isRightToLeft, isTrue);
    });

    test('an explicit script subtag decides, either way', () {
      // One language, two scripts, two directions.
      expect(const L10nLocale('az', script: 'Arab').isRightToLeft, isTrue);
      expect(const L10nLocale('az', script: 'Latn').isRightToLeft, isFalse);
      // A right-to-left language written in Latin, as romanized Urdu is.
      expect(const L10nLocale('ur', script: 'Latn').isRightToLeft, isFalse);
      // A left-to-right language written in Arabic.
      expect(const L10nLocale('pa', script: 'Arab').isRightToLeft, isTrue);
      expect(const L10nLocale('pa', script: 'Guru').isRightToLeft, isFalse);
    });

    test('a parsed tag answers the same as a constructed one', () {
      expect(L10nLocale.parse('ar_SA').isRightToLeft, isTrue);
      expect(L10nLocale.parse('az-arab-ir').isRightToLeft, isTrue);
      expect(L10nLocale.parse('zh_Hant_TW').isRightToLeft, isFalse);
    });

    test('an unknown script leaves the locale left to right', () {
      // Nothing is invented for a script the CLDR table does not list: a
      // guess here would be a layout flipped for no stated reason.
      expect(const L10nLocale('ar', script: 'Zzzz').isRightToLeft, isFalse);
      expect(const L10nLocale('xx').isRightToLeft, isFalse);
    });
  });
}
