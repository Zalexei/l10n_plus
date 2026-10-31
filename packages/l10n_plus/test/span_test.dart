import 'package:l10n_plus/l10n_plus.dart';
import 'package:test/test.dart';

/// The span type generated rich messages return.
///
/// Small, but it carries two claims the generator depends on: a span list
/// with no placeholder in it is `const`, and two spans with the same shape
/// are equal — which is what lets a test about a generated message read like
/// the sentence it came from.
void main() {
  group('equality is by value, including children', () {
    test('text spans compare their text', () {
      expect(const L10nTextSpan('a'), const L10nTextSpan('a'));
      expect(const L10nTextSpan('a'), isNot(const L10nTextSpan('b')));
    });

    test('tag spans compare the tag and every child', () {
      expect(
        const L10nTagSpan('b', [L10nTextSpan('x')]),
        const L10nTagSpan('b', [L10nTextSpan('x')]),
      );
      expect(
        const L10nTagSpan('b', [L10nTextSpan('x')]),
        isNot(const L10nTagSpan('i', [L10nTextSpan('x')])),
      );
      expect(
        const L10nTagSpan('b', [L10nTextSpan('x')]),
        isNot(const L10nTagSpan('b', [L10nTextSpan('y')])),
      );
      // A longer child list is not equal either.
      expect(
        const L10nTagSpan('b', [L10nTextSpan('x')]),
        isNot(const L10nTagSpan('b', [L10nTextSpan('x'), L10nTextSpan('y')])),
      );
    });

    test('equal spans hash equally, so a set folds them', () {
      // Built rather than const, so these really are two objects: a const
      // pair would be one canonical instance and prove nothing about
      // `hashCode`.
      final a = L10nTagSpan('b', [L10nTextSpan('x')]);
      final b = L10nTagSpan('b', [L10nTextSpan('x')]);
      expect(a.hashCode, b.hashCode);
      expect({a, b}, hasLength(1));
    });

    test('nesting is compared all the way down', () {
      expect(
        const L10nTagSpan('b', [
          L10nTagSpan('i', [L10nTextSpan('x')]),
        ]),
        const L10nTagSpan('b', [
          L10nTagSpan('i', [L10nTextSpan('x')]),
        ]),
      );
      expect(
        const L10nTagSpan('b', [
          L10nTagSpan('i', [L10nTextSpan('x')]),
        ]),
        isNot(
          const L10nTagSpan('b', [
            L10nTagSpan('i', [L10nTextSpan('y')]),
          ]),
        ),
      );
    });
  });

  test(
    'a const span tree is canonicalized, so reading it allocates nothing',
    () {
      const a = [
        L10nTextSpan('Read the '),
        L10nTagSpan('link', [L10nTextSpan('terms')]),
      ];
      const b = [
        L10nTextSpan('Read the '),
        L10nTagSpan('link', [L10nTextSpan('terms')]),
      ];
      expect(identical(a, b), isTrue);
    },
  );

  group('plainText', () {
    test('is the sentence with the markup dropped', () {
      expect(
        L10nSpan.plainText(const [
          L10nTextSpan('Read the '),
          L10nTagSpan('link', [L10nTextSpan('terms')]),
          L10nTextSpan(' now'),
        ]),
        'Read the terms now',
      );
    });

    test('reaches text at any depth', () {
      expect(
        L10nSpan.plainText(const [
          L10nTagSpan('b', [
            L10nTextSpan('a'),
            L10nTagSpan('i', [L10nTextSpan('b')]),
          ]),
        ]),
        'ab',
      );
    });

    test('is empty for no spans and for an empty tag', () {
      expect(L10nSpan.plainText(const []), '');
      expect(L10nSpan.plainText(const [L10nTagSpan('b', [])]), '');
    });
  });
}
