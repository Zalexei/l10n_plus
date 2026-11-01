@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/links/app_localizations.g.dart';

/// Runs the `links` golden instead of only reading it.
///
/// The golden test proves the call was written and `dart analyze` proves it
/// type checks. Neither proves the text that comes out is the target's: a link
/// resolved against the wrong locale, a propagated argument passed to the
/// wrong parameter, or a plural reached through another locale's conditions
/// all compile perfectly. This is the same file, executed.
void main() {
  const en = L10nLocale('en');

  final enT = AppLocalizations.forLocale(AppLocale.en);
  final ruT = AppLocalizations.forLocale(AppLocale.ru);

  tearDown(L10nOverrides.clear);

  group('what a link renders', () {
    test('each locale resolves the link against its own text', () {
      // The same message, the same link, two answers. Resolution happens per
      // locale while generating, so neither call consults anything.
      expect(enT.welcome, 'Welcome to Acme Cloud');
      expect(ruT.welcome, 'Добро пожаловать в Акме Клауд');
    });

    test('a linked message hands over its parameters', () {
      expect(
        enT.invitation(name: 'Ada'),
        'Hello, Ada — your trial of Acme Cloud has started',
      );
      expect(
        ruT.invitation(name: 'Ада'),
        'Здравствуйте, Ада — ваш пробный период Акме Клауд начался',
      );
    });

    test('a link to a plural selects with the target locale rules', () {
      // `cart` writes no plural at all: it links to one, so it takes the count
      // and the branch is chosen by the Russian conditions compiled into the
      // message it links to.
      expect(enT.cart(n: 1), 'Your Acme cart holds 1 item');
      expect(enT.cart(n: 5), 'Your Acme cart holds 5 items');
      expect(ruT.cart(n: 1), 'В корзине Акме: 1 товар');
      expect(ruT.cart(n: 3), 'В корзине Акме: 3 товара');
      expect(ruT.cart(n: 11), 'В корзине Акме: 11 товаров');
    });

    test('a link inside a plural branch renders in that branch', () {
      expect(enT.receipt(n: 1), 'One Acme charge');
      expect(enT.receipt(n: 4), '4 Acme charges');
      expect(ruT.receipt(n: 1), 'Одно списание Акме');
      expect(ruT.receipt(n: 3), '3 списания Акме');
      expect(ruT.receipt(n: 11), '11 списаний Акме');
    });

    test('two plurals in one sentence, each on its own count', () {
      // The thing linked translations are actually for, and the one capability
      // ICU cannot express at all: a message selects on exactly one argument,
      // so "3 files in 1 folder" needs two messages and a way to put one
      // inside the other. Each branch is still chosen by the conditions
      // compiled into its own message, in its own locale's rules.
      expect(enT.summary(n: 1, d: 3), '1 item in 3 folders');
      expect(enT.summary(n: 4, d: 1), '4 items in 1 folder');
      expect(ruT.summary(n: 1, d: 3), '1 товар в 3 папки');
      expect(ruT.summary(n: 5, d: 1), '5 товаров в 1 папка');
      expect(ruT.summary(n: 22, d: 11), '22 товара в 11 папок');
    });

    test('a quoted at sign is the two characters, not a link', () {
      expect(enT.tagline, 'Acme@:  Acme Cloud, simplified');
    });
  });

  group('what a link does with runtime overrides', () {
    test('overriding the target reaches everything that links to it', () {
      // The reason a link compiles to a call rather than to inlined text when
      // `runtime_overrides` is on. One bundle entry renames the product
      // everywhere it is mentioned, which is the thing a brand change
      // actually is.
      L10nOverrides.install(en, {'brand.name': 'Acme One'});
      expect(enT.welcome, 'Welcome to Acme One');
      expect(
        enT.invitation(name: 'Ada'),
        'Hello, Ada — your trial of Acme One has started',
      );
      // And nothing else moved: Russian was not overridden.
      expect(ruT.welcome, 'Добро пожаловать в Акме Клауд');
    });

    test('overriding a link in the chain reaches through it', () {
      L10nOverrides.install(en, {'greeting': 'Good morning, {name}'});
      expect(
        enT.invitation(name: 'Ada'),
        'Good morning, Ada — your trial of Acme Cloud has started',
      );
    });

    test('overriding the message that links replaces the whole of it', () {
      // An override is the words of one branch, and a link is resolved before
      // there are words: the linked part is simply inside the text being
      // replaced. The propagated argument is still a token, so the bundle can
      // place the count it never wrote itself.
      L10nOverrides.install(en, {'cart': 'Cart: {n}'});
      expect(enT.cart(n: 2), 'Cart: 2');
    });

    test('an override of the target is still refused for another build', () {
      // Nothing about links moved the fingerprint: the keys, branches and
      // tokens are what they were, so a bundle stamped before links existed
      // is still valid after them. Asserted by installing one for this build.
      expect(
        () => AppLocale.en.installOverrides({
          '@@fingerprint': '0123456789abcdef',
          'brand.name': 'Nope',
        }),
        throwsA(isA<L10nOverrideMismatch>()),
      );
      expect(enT.welcome, 'Welcome to Acme Cloud');
    });
  });
}
