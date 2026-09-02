import 'package:l10n_plus_generator/src/plural/cldr_plural_rules.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

const String _config = '''
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

String generated(Map<String, String> files) {
  final result = runGenerator(files, configYaml: _config);
  expect(
    errorsOf(result),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format(highlight: false)).join(),
  );
  return result.files.single.contents;
}

void main() {
  group('selectordinal', () {
    test('uses the ordinal rule table, not the cardinal one', () {
      final source = generated({
        'en.json':
            '{"place": "{n, selectordinal, '
            'one{#st} two{#nd} few{#rd} other{#th}}"}',
      });

      // English cardinals are one/other; ordinals are one/two/few/other.
      expect(source, contains(r"return '${n}st';"));
      // CLDR writes the English ordinal rules over `n`, not over `i`, so
      // 1.5 is `other` rather than `one`.
      expect(
        source,
        contains(r'$operands.n % 10 == 2 && $operands.n % 100 != 12'),
      );
      expect(
        source,
        contains(r'$operands.n % 10 == 3 && $operands.n % 100 != 13'),
      );
    });

    test('a language without ordinal categories falls through to other', () {
      final source = generated({
        'en.json': '{"p": "{n, selectordinal, one{#st} other{#th}}"}',
        'ru.json': '{"p": "{n, selectordinal, other{#-й}}"}',
      });
      expect(source, contains(r"return '$n-й';"));
    });

    test('warns about a branch the ordinal rules can never select', () {
      final result = runGenerator({
        'en.json': '{"p": "{n, selectordinal, other{#th}}"}',
        'ru.json': '{"p": "{n, selectordinal, one{#-й} other{#-й}}"}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      expect(codesOf(result), contains('unused_plural_category'));
    });

    test('rejects a language with no known ordinal rules', () {
      // Breton has cardinal rules and no ordinal ones, which is the common
      // shape: CLDR publishes ordinals for about half as many languages.
      expect(CldrPluralRules.forLanguage('br'), isNotNull);
      expect(CldrPluralRules.ordinalForLanguage('br'), isNull);
      final result = runGenerator({
        'en.json': '{"p": "{n, selectordinal, other{#th}}"}',
        'br.json': '{"p": "{n, selectordinal, other{#}}"}',
      }, configYaml: _config);

      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'unknown_ordinal_language',
      );
      // Having cardinal rules and not ordinal ones is worth saying, because
      // the obvious reading of "unknown language" is that the tag is wrong.
      expect(diagnostic.details, contains('It does have cardinal rules'));
    });

    test(
      'a cardinal plural in one locale and ordinal in another is an error',
      () {
        final result = runGenerator({
          'en.json': '{"p": "{n, selectordinal, other{#th}}"}',
          'ru.json': '{"p": "{n, plural, other{# штук}}"}',
        }, configYaml: _config);

        final diagnostic = result.diagnostics.singleWhere(
          (d) => d.code == 'plural_type_mismatch',
        );
        expect(diagnostic.details, contains('3rd'));
      },
    );

    test('a language may use ordinals without having cardinal branches', () {
      final source = generated({
        'en.json': '{"p": "{n, selectordinal, one{#st} other{#th}}"}',
        'ja.json': '{"p": "{n, selectordinal, other{#番}}"}',
      });
      expect(source, contains('番'));
    });
  });

  group('plural offset', () {
    test('subtracts before selecting a category and before rendering #', () {
      final source = generated({
        'en.json':
            '{"likes": "{count, plural, offset:1 '
            '=0{nobody} =1{you} one{you and # other} other{you and # others}}"}',
      });

      // `=N` still matches the original value; categories see the offset one.
      expect(source, contains('if (count == 0)'));
      expect(source, contains('if (count == 1)'));
      expect(source, contains(r'final $countOffset = count - 1;'));
      expect(source, contains(r'PluralOperands($countOffset)'));
      // The `=N` branches return before the subtraction happens.
      expect(
        source.indexOf('if (count == 1)'),
        lessThan(source.indexOf(r'final $countOffset')),
      );
      expect(source, contains(r"return 'you and ${$countOffset} other';"));
    });

    test('an offset nobody reads is not declared', () {
      final source = generated({
        'en.json': '{"n": "{count, plural, offset:1 other{nobody}}"}',
      });
      expect(source, isNot(contains('Offset')));
    });

    test('# inside an exact branch is still offset adjusted', () {
      final source = generated({
        'en.json':
            '{"n": "{count, plural, offset:1 =2{# other} other{# others}}"}',
      });
      expect(source, contains('if (count == 2)'));
      expect(source, contains(r"return '${$countOffset} other';"));
    });

    test('no offset means no extra local', () {
      final source = generated({
        'en.json': '{"n": "{count, plural, one{# item} other{# items}}"}',
      });
      expect(source, isNot(contains('Offset =')));
      expect(source, contains(r'PluralOperands(count)'));
    });

    test('a nested plural keeps its own number sign meaning', () {
      final source = generated({
        'en.json':
            '{"n": "{a, plural, offset:1 other{# and '
            '{b, plural, other{# more}}}}"}',
      });
      expect(source, contains(r'final $aOffset = a - 1;'));
      // The inner plural renders `#` as its own argument, not the outer one.
      expect(source, contains(r"return '$b more';"));
    });
  });
}
