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
