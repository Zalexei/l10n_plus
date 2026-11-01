@TestOn('vm')
library;

import 'package:test/test.dart';

import 'goldens/dynamic_keys/app_localizations.g.dart';

/// Runs the `dynamic_keys` golden instead of only reading it.
///
/// The golden test proves the enum and the lookup were written. What it cannot
/// prove is the thing a server-driven screen depends on: that a string from
/// outside lands on the right message, in the right locale, and that the two
/// steps compose with everything else the library does. This is the same
/// file, executed.
void main() {
  const en = L10nLocale('en');

  final enT = AppLocalizations.forLocale(AppLocale.en);
  final ruT = AppLocalizations.forLocale(AppLocale.ru);

  tearDown(L10nOverrides.clear);

  group('a string from outside', () {
    test('becomes a key, or nothing', () {
      expect(ErrorsKey.tryParse('offline'), ErrorsKey.offline);
      expect(ErrorsKey.tryParse('payment.declined'), ErrorsKey.paymentDeclined);
      expect(ErrorsKey.tryParse('rate_limited'), ErrorsKey.rateLimited);
      // The one place it can fail, and it fails by returning null rather than
      // by rendering the key on a screen.
      expect(ErrorsKey.tryParse('payment.stolen'), isNull);
      expect(ErrorsKey.tryParse(''), isNull);
      // The Dart name is not the key: the contract is the translation file's.
      expect(ErrorsKey.tryParse('rateLimited'), isNull);
      expect(ErrorsKey.tryParse('errors.offline'), isNull);
    });

    test('and the lookup it feeds cannot miss', () {
      // Total over the enum, so there is no second null to handle and no
      // fallback string to invent.
      for (final key in ErrorsKey.values) {
        expect(enT.errors[key], isNotEmpty, reason: key.key);
        expect(ruT.errors[key], isNotEmpty, reason: key.key);
      }
    });

    test('resolves against the locale, not the key', () {
      expect(enT.errors[ErrorsKey.paymentDeclined], 'Your card was declined');
      expect(ruT.errors[ErrorsKey.paymentDeclined], 'Карта отклонена');
      expect(enT.errors[ErrorsKey.rateLimited], 'Too many attempts');
      expect(ruT.errors[ErrorsKey.rateLimited], 'Слишком много попыток');
    });

    test('the shape a server-driven screen actually has', () {
      String render(String code) {
        final key = ErrorsKey.tryParse(code);
        return key == null ? enT.errors.unknown : enT.errors[key];
      }

      expect(render('offline'), 'You are offline');
      expect(render('payment.expired'), 'Your card has expired');
      // A code this build has never heard of falls back to a message the
      // project wrote for exactly that, rather than to the code itself.
      expect(render('quantum.flux'), 'Something went wrong');
    });

    test('values is the contract, in the file order', () {
      expect(ErrorsKey.values.map((value) => value.key), [
        'unknown',
        'offline',
        'rate_limited',
        'payment.declined',
        'payment.expired',
      ]);
    });
  });

  group('the typed way still works', () {
    test('the members are there and allocate nothing', () {
      expect(enT.errors.offline, 'You are offline');
      expect(enT.errors.payment.declined, 'Your card was declined');
      expect(identical(enT.errors, enT.errors), isTrue);
      expect(identical(enT.errors.payment, enT.errors.payment), isTrue);
    });

    test('a namespace nobody addressed by key is untouched', () {
      expect(enT.auth.title, 'Log in');
      expect(enT.auth.greeting(name: 'Ada'), 'Hello again, Ada');
    });
  });

  group('and it composes with runtime overrides', () {
    test('overriding a message overrides it through the lookup', () {
      // The reason the lookup delegates to the members instead of repeating
      // their text: one bundle entry changes both ways of reading it.
      L10nOverrides.install(en, {'errors.offline': 'No connection'});
      expect(enT.errors.offline, 'No connection');
      expect(enT.errors[ErrorsKey.offline], 'No connection');
    });

    test('a nested message too', () {
      L10nOverrides.install(en, {'errors.payment.declined': 'Card refused'});
      expect(enT.errors[ErrorsKey.paymentDeclined], 'Card refused');
      expect(ruT.errors[ErrorsKey.paymentDeclined], 'Карта отклонена');
    });

    test('an override cannot add a key the build does not have', () {
      // A bundle is text for messages that exist; `check-overrides` refuses
      // the rest. So the set of keys is still decided at build time, which is
      // the whole difference from a string keyed table.
      L10nOverrides.install(en, {'errors.quantum': 'Nope'});
      expect(ErrorsKey.tryParse('quantum'), isNull);
      expect(ErrorsKey.values.length, 5);
    });
  });
}
