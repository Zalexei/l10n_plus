import 'package:l10n_plus/l10n_plus.dart';
import 'package:test/test.dart';

void main() {
  const en = L10nLocale('en');
  const ru = L10nLocale('ru');
  const enUs = L10nLocale('en', country: 'US');

  tearDown(L10nOverrides.clear);

  group('the store', () {
    test('nothing is installed by default', () {
      expect(L10nOverrides.isEmpty, isTrue);
      expect(L10nOverrides.text(en, 'a.b'), isNull);
      expect(L10nOverrides.locales, isEmpty);
    });

    test('a one form message is found by its key', () {
      L10nOverrides.install(en, {'a.b': 'Hello'});
      expect(L10nOverrides.text(en, 'a.b'), 'Hello');
      expect(L10nOverrides.text(en, 'a.c'), isNull);
    });

    test('a branch is found by its name', () {
      L10nOverrides.install(en, {
        'a.b': {'one': 'one thing', 'other': 'things'},
      });
      expect(L10nOverrides.text(en, 'a.b', 'one'), 'one thing');
      expect(L10nOverrides.text(en, 'a.b', 'other'), 'things');
      expect(L10nOverrides.text(en, 'a.b', 'few'), isNull);
    });

    test('the two shapes never substitute for one another', () {
      // A single text spread over a plural's branches is how a plural
      // silently stops pluralizing, so it is not spread.
      L10nOverrides.install(en, {'a.b': 'Hello'});
      expect(L10nOverrides.text(en, 'a.b', 'one'), isNull);

      L10nOverrides.install(en, {
        'a.b': {'one': 'one thing'},
      });
      expect(L10nOverrides.text(en, 'a.b'), isNull);
    });

    test('a value of the wrong type is ignored rather than thrown on', () {
      // A bundle is data from the network; a number where a string belongs
      // must not take the app down.
      L10nOverrides.install(en, {
        'a.b': 42,
        'a.c': {'one': 7},
      });
      expect(L10nOverrides.text(en, 'a.b'), isNull);
      expect(L10nOverrides.text(en, 'a.c', 'one'), isNull);
    });

    test('locales are kept apart, region included', () {
      L10nOverrides.install(en, {'a.b': 'Hello'});
      L10nOverrides.install(ru, {'a.b': 'Привет'});
      expect(L10nOverrides.text(en, 'a.b'), 'Hello');
      expect(L10nOverrides.text(ru, 'a.b'), 'Привет');
      // `en_US` is a different locale, and the generated code for it asks for
      // itself. Nothing falls back here: resolution already happened when the
      // translations were chosen.
      expect(L10nOverrides.text(enUs, 'a.b'), isNull);
    });

    test('installing replaces that locale and leaves the others', () {
      L10nOverrides.install(en, {'a.b': 'Hello', 'a.c': 'Bye'});
      L10nOverrides.install(ru, {'a.b': 'Привет'});
      L10nOverrides.install(en, {'a.b': 'Hi'});
      expect(L10nOverrides.text(en, 'a.b'), 'Hi');
      expect(L10nOverrides.text(en, 'a.c'), isNull);
      expect(L10nOverrides.text(ru, 'a.b'), 'Привет');
    });

    test('clear takes one locale, or all of them', () {
      L10nOverrides.install(en, {'a.b': 'Hello'});
      L10nOverrides.install(ru, {'a.b': 'Привет'});

      L10nOverrides.clear(en);
      expect(L10nOverrides.text(en, 'a.b'), isNull);
      expect(L10nOverrides.text(ru, 'a.b'), 'Привет');
      expect(L10nOverrides.isEmpty, isFalse);

      L10nOverrides.clear();
      expect(L10nOverrides.isEmpty, isTrue);
      expect(L10nOverrides.locales, isEmpty);
    });

    test('the outer map is copied, so the caller may keep mutating theirs', () {
      final bundle = <String, Object>{'a.b': 'Hello'};
      L10nOverrides.install(en, bundle);
      bundle['a.b'] = 'Changed';
      bundle['a.c'] = 'Added';
      expect(L10nOverrides.text(en, 'a.b'), 'Hello');
      expect(L10nOverrides.text(en, 'a.c'), isNull);
    });

    group('listeners', () {
      test('install and clear notify', () {
        final events = <String>[];
        void listener() => events.add('x');
        L10nOverrides.addListener(listener);
        addTearDown(() => L10nOverrides.removeListener(listener));

        L10nOverrides.install(en, {'a.b': 'Hello'});
        L10nOverrides.install(ru, {'a.b': 'Привет'});
        L10nOverrides.clear(en);
        L10nOverrides.clear();
        expect(events, hasLength(4));
      });

      test('clearing nothing is not an event', () {
        var notified = 0;
        void listener() => notified++;
        L10nOverrides.addListener(listener);
        addTearDown(() => L10nOverrides.removeListener(listener));

        L10nOverrides.clear();
        L10nOverrides.clear(en);
        expect(notified, 0);
      });

      test('a removed listener stops hearing', () {
        var notified = 0;
        void listener() => notified++;
        L10nOverrides.addListener(listener);
        L10nOverrides.install(en, {'a.b': 'Hello'});
        L10nOverrides.removeListener(listener);
        L10nOverrides.install(en, {'a.b': 'Hi'});
        expect(notified, 1);
      });

      test('a listener may remove itself while being called', () {
        // Notification walks a copy, so a controller disposing on the first
        // event cannot corrupt the walk.
        var notified = 0;
        late void Function() listener;
        listener = () {
          notified++;
          L10nOverrides.removeListener(listener);
        };
        L10nOverrides.addListener(listener);
        L10nOverrides.install(en, {'a.b': 'Hello'});
        L10nOverrides.install(en, {'a.b': 'Hi'});
        expect(notified, 1);
      });
    });
  });

  group('fill', () {
    test('substitutes one token', () {
      expect(
        L10nOverrides.fill('Hello, {name}', {'name': 'Alex'}),
        'Hello, Alex',
      );
    });

    test('substitutes several, in any order', () {
      expect(
        L10nOverrides.fill('{greeting}, {name} of {place}', {
          'name': 'Alex',
          'greeting': 'Hello',
          'place': 'Tel Aviv',
        }),
        'Hello, Alex of Tel Aviv',
      );
    });

    test('substitutes a token more than once', () {
      expect(
        L10nOverrides.fill('{name}, {name} and {name}', {'name': 'Alex'}),
        'Alex, Alex and Alex',
      );
    });

    test('a token adjacent to text keeps both', () {
      expect(
        L10nOverrides.fill('[{name}]{name}x{name}', {'name': 'A'}),
        '[A]AxA',
      );
    });

    test('a token at either end', () {
      expect(L10nOverrides.fill('{name}', {'name': 'A'}), 'A');
      expect(L10nOverrides.fill('{a} {b}', {'a': 'x', 'b': 'y'}), 'x y');
    });

    test('the number sign is the count, wherever it is', () {
      expect(L10nOverrides.fill('# of #', {'#': '3'}), '3 of 3');
      expect(L10nOverrides.fill('#items', {'#': '3'}), '3items');
    });

    test('a nested choice token is a token like any other', () {
      expect(
        L10nOverrides.fill('You have {#0} linked', {'#0': '3 cards'}),
        'You have 3 cards linked',
      );
    });

    test('an unknown token is left exactly as it stands', () {
      // A wrong override must not crash a running app; `check-overrides` is
      // what stops it shipping.
      expect(
        L10nOverrides.fill('Hello, {nmae}', {'name': 'Alex'}),
        'Hello, {nmae}',
      );
      expect(L10nOverrides.fill('# left', {'name': 'Alex'}), '# left');
    });

    test('text that merely looks like a token is text', () {
      // No ICU quoting to learn: anything that is not an identifier, or `#n`,
      // is left alone.
      for (final template in [
        'It is a {literal brace}',
        'A {} pair',
        'Costs {4.50}',
        'Unclosed {name',
        'Backwards }name{',
        '{count, plural, one{#}}',
      ]) {
        expect(
          L10nOverrides.fill(template, {'name': 'A', 'count': '3'}),
          template,
          reason: template,
        );
      }
    });

    test('an empty template, and no values, are returned as they are', () {
      expect(L10nOverrides.fill('', {'name': 'A'}), '');
      expect(L10nOverrides.fill('Hello, {name}', const {}), 'Hello, {name}');
    });

    test('a substituted value is not scanned again', () {
      // One pass: a value that happens to look like a token stays text, so no
      // bundle can build a loop out of its own translations.
      expect(L10nOverrides.fill('{a}', {'a': '{a}', 'b': 'x'}), '{a}');
      expect(L10nOverrides.fill('{a}', {'a': '{b}', 'b': 'x'}), '{b}');
    });
  });

  group('the fingerprint', () {
    const key = L10nOverrides.fingerprintKey;

    test('metadata is not a message, so it is not stored', () {
      L10nOverrides.install(en, {key: 'abc', '@@locale': 'en', 'a.b': 'Hello'});
      expect(L10nOverrides.text(en, 'a.b'), 'Hello');
      expect(L10nOverrides.text(en, key), isNull);
      expect(L10nOverrides.text(en, '@@locale'), isNull);
    });

    test('a bundle for this build is installed', () {
      L10nOverrides.install(en, {
        key: 'abc',
        'a.b': 'Hello',
      }, fingerprint: 'abc');
      expect(L10nOverrides.text(en, 'a.b'), 'Hello');
    });

    test('a bundle for another build is refused, and nothing is kept', () {
      L10nOverrides.install(en, {'a.b': 'Hello'});
      expect(
        () => L10nOverrides.install(en, {
          key: 'older',
          'a.b': 'Hi',
        }, fingerprint: 'abc'),
        throwsA(isA<L10nOverrideMismatch>()),
      );
      // Install replaces, so a refusal that had got halfway would have
      // dropped what was there. The previous bundle is untouched.
      expect(L10nOverrides.text(en, 'a.b'), 'Hello');
    });

    test('the mismatch says both surfaces and which locale', () {
      final error = L10nOverrideMismatch(
        locale: ru,
        declared: 'older',
        expected: 'abc',
      );
      expect('$error', contains('ru'));
      expect('$error', contains('older'));
      expect('$error', contains('abc'));
    });

    test('nothing is checked when either side states nothing', () {
      // A bundle that states no surface was checked by nothing, and
      // `check-overrides` is where this project refuses that. A caller that
      // passes none — a test installing three strings — has no build to
      // speak of.
      L10nOverrides.install(en, {'a.b': 'Hello'}, fingerprint: 'abc');
      expect(L10nOverrides.text(en, 'a.b'), 'Hello');
      L10nOverrides.install(ru, {key: 'anything', 'a.b': 'Привет'});
      expect(L10nOverrides.text(ru, 'a.b'), 'Привет');
    });
  });
}
