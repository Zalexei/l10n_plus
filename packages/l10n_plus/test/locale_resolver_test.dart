import 'package:l10n_plus/l10n_plus.dart';
import 'package:test/test.dart';

enum _Locale implements AppLocaleBase {
  en(L10nLocale('en')),
  enGb(L10nLocale('en', country: 'GB')),
  pt(L10nLocale('pt')),
  ptBr(L10nLocale('pt', country: 'BR'));

  const _Locale(this.l10nLocale);

  @override
  final L10nLocale l10nLocale;
}

void main() {
  _regionFallbackOrder();
  const supported = _Locale.values;

  _Locale resolve(String? tag) => L10nLocaleResolver.resolve(
    requested: tag == null ? null : L10nLocale.parse(tag),
    supported: supported,
    fallback: _Locale.en,
  );

  test('prefers an exact match', () {
    expect(resolve('pt_BR'), _Locale.ptBr);
    expect(resolve('en_GB'), _Locale.enGb);
  });

  test('falls back along the lineage', () {
    expect(resolve('pt_PT'), _Locale.pt);
  });

  test('falls back to any locale of the same language', () {
    expect(
      L10nLocaleResolver.resolve(
        requested: L10nLocale.parse('en_AU'),
        supported: const [_Locale.enGb, _Locale.pt],
        fallback: _Locale.pt,
      ),
      _Locale.enGb,
    );
  });

  test('falls back to the fallback locale', () {
    expect(resolve('de'), _Locale.en);
    expect(resolve(null), _Locale.en);
  });

  test('rejects an empty supported list', () {
    expect(
      () => L10nLocaleResolver.resolve(
        requested: const L10nLocale('en'),
        supported: const <_Locale>[],
        fallback: _Locale.en,
      ),
      throwsArgumentError,
    );
  });
}

/// Locales in the order a generated enum lists them: sorted by tag.
enum _Region implements AppLocaleBase {
  enAu(L10nLocale('en', country: 'AU')),
  enGb(L10nLocale('en', country: 'GB')),
  ru(L10nLocale('ru'));

  const _Region(this.l10nLocale);

  @override
  final L10nLocale l10nLocale;
}

/// The region fallback picks the first supported locale of the same language.
///
/// Pinned because the choice is arbitrary: `en_NZ` resolves to `en_AU` over
/// `en_GB` because `AU` comes first in the list, not because anyone decided a
/// New Zealander prefers Australian English. A change here changes what every
/// app with regional locales renders, so it should have to break a test that
/// says so out loud.
void _regionFallbackOrder() {
  group('region fallback order', () {
    test('the first supported locale of the language wins', () {
      expect(
        L10nLocaleResolver.resolve(
          requested: L10nLocale.parse('en_NZ'),
          supported: _Region.values,
          fallback: _Region.ru,
        ),
        _Region.enAu,
      );
    });

    test('reordering the list changes the answer', () {
      expect(
        L10nLocaleResolver.resolve(
          requested: L10nLocale.parse('en_NZ'),
          supported: const [_Region.enGb, _Region.enAu, _Region.ru],
          fallback: _Region.ru,
        ),
        _Region.enGb,
      );
    });

    test('an exact region still beats the ordering', () {
      expect(
        L10nLocaleResolver.resolve(
          requested: L10nLocale.parse('en_GB'),
          supported: _Region.values,
          fallback: _Region.ru,
        ),
        _Region.enGb,
      );
    });

    test('a bare language in the list beats both regions', () {
      // `en_NZ` walks its lineage first, so a plain `en` is found before the
      // language scan runs at all. That is how a project states the
      // preference the resolver refuses to guess.
      expect(
        L10nLocaleResolver.resolve(
          requested: L10nLocale.parse('en_NZ'),
          supported: const [_Locale.enGb, _Locale.en],
          fallback: _Locale.en,
        ),
        _Locale.en,
      );
    });

    test('another language falls back', () {
      expect(
        L10nLocaleResolver.resolve(
          requested: L10nLocale.parse('ja'),
          supported: _Region.values,
          fallback: _Region.ru,
        ),
        _Region.ru,
      );
    });
  });
}
