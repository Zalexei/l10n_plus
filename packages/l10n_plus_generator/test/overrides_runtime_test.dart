@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/overrides/app_localizations.g.dart';

/// Runs the `runtime_overrides` golden instead of only reading it.
///
/// The golden test proves the lookups were written and `dart analyze` proves
/// they type check. Neither proves the right one is consulted: a branch keyed
/// by the wrong name, a token substituted with the unformatted value, or a
/// Russian `many` reached through an English condition all compile perfectly.
/// This is the same file, executed.
void main() {
  const en = L10nLocale('en');
  const ru = L10nLocale('ru');

  final enT = AppLocalizations.forLocale(AppLocale.en);
  final ruT = AppLocalizations.forLocale(AppLocale.ru);

  // Global state, so every test starts from nothing installed. This is the
  // hazard the store's documentation names, and the answer it names.
  tearDown(L10nOverrides.clear);

  test('nothing installed renders exactly the compiled text', () {
    expect(enT.auth.login.title, 'Log in');
    expect(enT.wallet.transactions(count: 2), '2 transactions');
    expect(L10nOverrides.isEmpty, isTrue);
  });

  test('a message with one form is replaced by its text', () {
    L10nOverrides.install(en, {'auth.login.title': 'Sign in'});
    expect(enT.auth.login.title, 'Sign in');
  });

  test('an argument is substituted into the override', () {
    L10nOverrides.install(en, {'auth.login.subtitle': 'Hello again, {name}!'});
    expect(enT.auth.login.subtitle(name: 'Alex'), 'Hello again, Alex!');
  });

  test('formatting is still compiled: the token carries the rendering', () {
    // The override says `{amount}`, and what arrives is what the generated
    // `NumberFormat.currency` produced — which is the whole reason the
    // override cannot be allowed to carry `{amount, number, currency}`.
    L10nOverrides.install(en, {'wallet.total': 'Charged {amount} today'});
    expect(enT.wallet.total(amount: 1234.5), 'Charged USD1,234.50 today');

    L10nOverrides.install(ru, {'wallet.total': 'Списано {amount}'});
    // Russian groups with a non breaking space and puts the code last, which
    // is `intl` deciding it and not this library.
    expect(ruT.wallet.total(amount: 1234.5), 'Списано 1 234,50 USD');
  });

  group('a plural is overridden per branch', () {
    setUp(() {
      L10nOverrides.install(en, {
        'wallet.transactions': {
          '=0': 'Nothing here yet',
          'one': 'Exactly # payment',
          'other': '# payments',
        },
      });
    });

    test('the compiled condition still chooses', () {
      expect(enT.wallet.transactions(count: 0), 'Nothing here yet');
      expect(enT.wallet.transactions(count: 1), 'Exactly 1 payment');
      expect(enT.wallet.transactions(count: 2), '2 payments');
      expect(enT.wallet.transactions(count: 21), '21 payments');
    });

    test('a branch the bundle leaves out keeps its compiled text', () {
      L10nOverrides.install(en, {
        'wallet.transactions': {'=0': 'Nothing here yet'},
      });
      expect(enT.wallet.transactions(count: 0), 'Nothing here yet');
      expect(enT.wallet.transactions(count: 1), '1 transaction');
    });
  });

  test("a locale's own categories are the branches it consults", () {
    // The point of the feature, and the one check nobody else can make: `ru`
    // has four categories and English two, and 21, 3 and 11 land in three
    // different ones. No rule table and no parser reached the runtime to do
    // it — the conditions were compiled in.
    L10nOverrides.install(ru, {
      'wallet.transactions': {
        '=0': 'Пусто',
        'one': '# платёж',
        'few': '# платежа',
        'many': '# платежей',
        'other': '# платежа',
      },
    });
    expect(ruT.wallet.transactions(count: 0), 'Пусто');
    expect(ruT.wallet.transactions(count: 1), '1 платёж');
    expect(ruT.wallet.transactions(count: 21), '21 платёж');
    expect(ruT.wallet.transactions(count: 3), '3 платежа');
    expect(ruT.wallet.transactions(count: 11), '11 платежей');
    expect(ruT.wallet.transactions(count: 5), '5 платежей');
  });

  test('a Russian category is not a branch of English', () {
    // `few` is nothing in English, so the store is asked for a branch the
    // generated code never consults and the compiled text stands. The build
    // time check is what turns this into an error instead of a mystery.
    L10nOverrides.install(en, {
      'wallet.transactions': {'few': 'нет'},
    });
    expect(enT.wallet.transactions(count: 3), '3 transactions');
  });

  test('an offset plural sees the adjusted count', () {
    L10nOverrides.install(en, {
      'wallet.likes': {'one': 'You and # friend', 'other': 'You and # friends'},
    });
    expect(enT.wallet.likes(count: 2), 'You and 1 friend');
    expect(enT.wallet.likes(count: 4), 'You and 3 friends');
    expect(enT.wallet.likes(count: 0), 'Nobody');
  });

  group('a nested choice', () {
    test(
      'the sentence around it is one slot, with the rendering as a token',
      () {
        L10nOverrides.install(en, {'wallet.summary': 'You now have {#0}'});
        expect(enT.wallet.summary(count: 1), 'You now have 1 card');
        expect(enT.wallet.summary(count: 3), 'You now have 3 cards');
      },
    );

    test('its own branches sit under its number', () {
      L10nOverrides.install(en, {
        'wallet.summary': {'0/one': '# bank card', '0/other': '# bank cards'},
      });
      expect(enT.wallet.summary(count: 1), 'You have 1 bank card linked');
      expect(enT.wallet.summary(count: 3), 'You have 3 bank cards linked');
    });

    test('both at once, which is what makes a whole reword possible', () {
      L10nOverrides.install(en, {
        'wallet.summary': 'Linked: {#0}',
        // The same key carries one of the two shapes, so a message needing
        // both is two keys' worth of text in one — the frame, and the branch.
      });
      expect(enT.wallet.summary(count: 2), 'Linked: 2 cards');
    });

    test('an ordinal nests the same way, on its own rule table', () {
      L10nOverrides.install(en, {
        'wallet.rank': {'0/one': '#st place', '0/two': '#nd place'},
      });
      expect(enT.wallet.rank(place: 1), '1st place largest');
      expect(enT.wallet.rank(place: 2), '2nd place largest');
      expect(enT.wallet.rank(place: 4), '4th largest');
    });
  });

  test('a select is overridden by case name', () {
    L10nOverrides.install(en, {
      'profile.greeting': {'male': 'Hi Mr {name}', 'female': 'Hi Ms {name}'},
    });
    expect(
      enT.profile.greeting(gender: ProfileGreetingGender.male, name: 'Sam'),
      'Hi Mr Sam',
    );
    expect(
      enT.profile.greeting(gender: ProfileGreetingGender.other, name: 'Sam'),
      'Welcome, Sam',
    );
  });

  test('locales do not leak into one another', () {
    L10nOverrides.install(en, {'auth.login.title': 'Sign in'});
    expect(enT.auth.login.title, 'Sign in');
    expect(ruT.auth.login.title, 'Войти');

    L10nOverrides.install(ru, {'auth.login.title': 'Вход'});
    expect(ruT.auth.login.title, 'Вход');
    expect(enT.auth.login.title, 'Sign in');

    L10nOverrides.clear(en);
    expect(enT.auth.login.title, 'Log in');
    expect(ruT.auth.login.title, 'Вход');
  });

  test('installing replaces that locale rather than merging into it', () {
    L10nOverrides.install(en, {
      'auth.login.title': 'Sign in',
      'profile.quoted_key': 'Braces: {literal brace}',
    });
    L10nOverrides.install(en, {'auth.login.title': 'Log on'});
    expect(enT.auth.login.title, 'Log on');
    // Dropped from the bundle, so back to the compiled text.
    expect(enT.profile.quotedKey, 'It\'s a {literal brace}');
  });

  test('text that merely looks like a token survives', () {
    // `{literal brace}` is not an identifier, so no bundle has to learn ICU
    // quoting to write a brace.
    L10nOverrides.install(en, {
      'profile.quoted_key': 'Still a {literal brace}',
    });
    expect(enT.profile.quotedKey, 'Still a {literal brace}');
  });

  test('a token nothing names is left in place rather than thrown on', () {
    // A wrong override must not crash a running app. `check-overrides` is
    // what makes this unreachable in a project that runs it.
    L10nOverrides.install(en, {'auth.login.subtitle': 'Hello {nmae}'});
    expect(enT.auth.login.subtitle(name: 'Alex'), 'Hello {nmae}');
  });

  test('the wrong shape is ignored, not guessed at', () {
    // One text for a message that branches would have to be spread over its
    // branches, which is how a plural silently stops pluralizing.
    L10nOverrides.install(en, {'wallet.transactions': 'Some payments'});
    expect(enT.wallet.transactions(count: 2), '2 transactions');

    // And branches for a message that has none name nothing.
    L10nOverrides.install(en, {
      'auth.login.title': {'one': 'Sign in'},
    });
    expect(enT.auth.login.title, 'Log in');
  });

  test('a key the project does not define does nothing', () {
    L10nOverrides.install(en, {'auth.login.ttile': 'Sign in'});
    expect(enT.auth.login.title, 'Log in');
  });

  test('installing notifies, so nothing can go silently stale', () {
    var notified = 0;
    void listener() => notified++;
    L10nOverrides.addListener(listener);
    addTearDown(() => L10nOverrides.removeListener(listener));

    L10nOverrides.install(en, {'auth.login.title': 'Sign in'});
    expect(notified, 1);
    L10nOverrides.clear(en);
    expect(notified, 2);
    // Nothing to clear is not a change, so it is not an event.
    L10nOverrides.clear(en);
    expect(notified, 2);
  });

  test('the store is a copy, so the caller may keep its map', () {
    final bundle = <String, Object>{'auth.login.title': 'Sign in'};
    L10nOverrides.install(en, bundle);
    bundle['auth.login.title'] = 'Something else';
    expect(enT.auth.login.title, 'Sign in');
  });
}
