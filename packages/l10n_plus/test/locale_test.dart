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
}
