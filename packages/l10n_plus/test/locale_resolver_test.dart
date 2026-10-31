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
  en(L10nLocale('en')),
  enAu(L10nLocale('en', country: 'AU')),
  enGb(L10nLocale('en', country: 'GB')),
  ru(L10nLocale('ru'));

  const _Region(this.l10nLocale);

  @override
  final L10nLocale l10nLocale;
}

/// Chinese written two ways, to pin the one script rule the resolver applies.
enum _Script implements AppLocaleBase {
  zhHansCn(L10nLocale('zh', script: 'Hans', country: 'CN')),
  zhHantTw(L10nLocale('zh', script: 'Hant', country: 'TW')),
  en(L10nLocale('en'));

  const _Script(this.l10nLocale);

  @override
  final L10nLocale l10nLocale;
}

/// The region fallback is a rule, not an artefact of the list order.
///
/// Both halves matter and both are pinned here, because this is behaviour
/// every app with regional locales renders: a region-less locale always wins
/// over a regional sibling, and when only siblings exist the winner is chosen
/// by a total order over the locales rather than by whichever came first.
void _regionFallbackOrder() {
  group('region fallback order', () {
    test('a region-less locale wins, wherever it sits in the list', () {
      // `en_NZ` walks its lineage (`en_NZ`, then `en`) before any sibling is
      // considered, so a plain `en` is the answer and its position cannot
      // change that. This is how a project states the preference the resolver
      // refuses to guess.
      for (final order in const [
        [_Region.en, _Region.enAu, _Region.enGb, _Region.ru],
        [_Region.enAu, _Region.enGb, _Region.en, _Region.ru],
        [_Region.enGb, _Region.ru, _Region.enAu, _Region.en],
      ]) {
        expect(
          L10nLocaleResolver.resolve(
            requested: L10nLocale.parse('en_NZ'),
            supported: order,
            fallback: _Region.ru,
          ),
          _Region.en,
          reason: 'the generic locale must win for $order',
        );
      }
    });

    test('with only siblings, the lowest tag wins', () {
      // `en_NZ` against `en_AU` and `en_GB` resolves to `en_AU` because
      // `en-AU` sorts before `en-GB`. The value is the same one the old
      // first-match resolver produced, but now for a stated reason instead of
      // because `AU` happened to be listed first: the resolver claims no
      // affinity between New Zealand and Australia, only a tie-break that is
      // the same for every caller. The honest alternative — refusing to pick
      // and going to the fallback — would render Russian to a New Zealander
      // while English translations sat right there.
      expect(
        L10nLocaleResolver.resolve(
          requested: L10nLocale.parse('en_NZ'),
          supported: const [_Region.enAu, _Region.enGb, _Region.ru],
          fallback: _Region.ru,
        ),
        _Region.enAu,
      );
    });

    test('reordering the list does not change the answer', () {
      // The inverse of what this test used to assert. The old resolver took
      // the first sibling offered, so listing `en_GB` first made it the
      // answer, and the answer therefore depended on how the translation
      // files were named. Order-independence is the fix, so the test that
      // pinned the old behaviour has to assert the opposite.
      expect(
        L10nLocaleResolver.resolve(
          requested: L10nLocale.parse('en_NZ'),
          supported: const [_Region.enGb, _Region.enAu, _Region.ru],
          fallback: _Region.ru,
        ),
        _Region.enAu,
      );
      expect(
        L10nLocaleResolver.resolve(
          requested: L10nLocale.parse('en_NZ'),
          supported: const [_Region.ru, _Region.enGb, _Region.enAu],
          fallback: _Region.ru,
        ),
        _Region.enAu,
      );
    });

    test('an exact region still beats the sibling rule', () {
      expect(
        L10nLocaleResolver.resolve(
          requested: L10nLocale.parse('en_GB'),
          supported: _Region.values,
          fallback: _Region.ru,
        ),
        _Region.enGb,
      );
    });

    test('a matching script beats the tag tie-break', () {
      // `zh-Hans-CN` sorts before `zh-Hant-TW`, so a purely alphabetical rule
      // would hand a Hong Kong reader simplified characters. Script is the one
      // thing the resolver knows without CLDR's affinity table, so it outranks
      // the tie-break — in either list order.
      for (final order in const [
        [_Script.zhHansCn, _Script.zhHantTw, _Script.en],
        [_Script.zhHantTw, _Script.zhHansCn, _Script.en],
      ]) {
        expect(
          L10nLocaleResolver.resolve(
            requested: L10nLocale.parse('zh_Hant_HK'),
            supported: order,
            fallback: _Script.en,
          ),
          _Script.zhHantTw,
          reason: 'the matching script must win for $order',
        );
      }
    });

    test('an unmarked script outranks a conflicting one', () {
      // `en_Latn_NZ` prefers plain `en_AU` over `en_Cyrl_BY`: an absent script
      // conflicts with nothing, a different one conflicts outright. Without
      // this the Cyrillic tag would win on `en-Cyrl-BY` < `en-Latn-AU`.
      expect(
        L10nLocaleResolver.resolve(
          requested: L10nLocale.parse('en_Latn_NZ'),
          supported: const [_Mixed.enCyrlBy, _Mixed.enAu, _Mixed.ru],
          fallback: _Mixed.ru,
        ),
        _Mixed.enAu,
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

/// English tagged with scripts, to pin the unmarked-beats-conflicting rank.
enum _Mixed implements AppLocaleBase {
  enAu(L10nLocale('en', country: 'AU')),
  enCyrlBy(L10nLocale('en', script: 'Cyrl', country: 'BY')),
  ru(L10nLocale('ru'));

  const _Mixed(this.l10nLocale);

  @override
  final L10nLocale l10nLocale;
}
