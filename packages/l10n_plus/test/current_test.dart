import 'package:l10n_plus/l10n_plus.dart';
import 'package:test/test.dart';

enum _Locale implements AppLocaleBase {
  en,
  ru;

  @override
  L10nLocale get l10nLocale => L10nLocale(name);
}

void main() {
  late L10nCurrent<_Locale> cell;
  setUp(() => cell = L10nCurrent<_Locale>());

  test('starts empty', () => expect(cell.locale, isNull));

  test('install without an owner always succeeds', () {
    cell.install(_Locale.ru);
    cell.install(_Locale.en);
    expect(cell.locale, _Locale.en);
  });

  test('the owner may install again', () {
    final owner = Object();
    cell.install(_Locale.en, owner: owner);
    cell.install(_Locale.ru, owner: owner);
    expect(cell.locale, _Locale.ru);
  });

  test('a second live owner fails the assert', () {
    cell.install(_Locale.en, owner: Object());
    expect(
      () => cell.install(_Locale.ru, owner: Object()),
      throwsA(isA<AssertionError>()),
    );
  });

  test('release by the owner empties it, by anyone else does nothing', () {
    final owner = Object();
    cell.install(_Locale.ru, owner: owner);
    cell.release(Object());
    expect(cell.locale, _Locale.ru);
    cell.release(owner);
    expect(cell.locale, isNull);
    cell.install(_Locale.en, owner: Object());
    expect(cell.locale, _Locale.en);
  });

  test('an install without an owner takes the cell over', () {
    final owner = Object();
    cell.install(_Locale.en, owner: owner);
    cell.install(_Locale.ru);
    cell.release(owner);
    expect(cell.locale, _Locale.ru);
  });

  test('reset empties it whoever installed it', () {
    cell.install(_Locale.ru, owner: Object());
    cell.reset();
    expect(cell.locale, isNull);
    cell.install(_Locale.en, owner: Object());
  });
}
