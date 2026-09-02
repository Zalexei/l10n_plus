import 'package:test/test.dart';

import 'support/fixture.dart';

String _config({bool? formatPluralNumbers}) =>
    '''
base_locale: en
fallback_locale: en
${formatPluralNumbers == null ? '' : 'format_plural_numbers: $formatPluralNumbers'}
flutter:
  enabled: false
''';

String generated(Map<String, String> files, {bool? formatPluralNumbers}) {
  final result = runGenerator(
    files,
    configYaml: _config(formatPluralNumbers: formatPluralNumbers),
  );
  expect(
    errorsOf(result),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format(highlight: false)).join(),
  );
  return result.files.single.contents;
}

const Map<String, String> _cards = {
  'en.json': '{"cards": "{count, plural, one{# card} other{# cards}}"}',
};

void main() {
  group('format_plural_numbers', () {
    test('defaults to off, interpolating the raw number', () {
      final source = generated(_cards);
      expect(source, contains(r"return '$count cards';"));
      expect(source, isNot(contains('intl')));
      expect(source, isNot(contains('NumberFormat')));
    });

    test('explicit false is the same as omitting it', () {
      expect(generated(_cards, formatPluralNumbers: false), generated(_cards));
    });

    test('true renders # through the locale number format', () {
      final source = generated(_cards, formatPluralNumbers: true);
      expect(
        source,
        contains(r"return '${_enNumberDecimalPattern.format(count)} cards';"),
      );
      expect(source, contains("NumberFormat.decimalPattern('en')"));
      expect(source, contains("import 'package:intl/intl.dart';"));
    });

    test('turning it on is what pulls intl into a plural-only project', () {
      expect(generated(_cards), isNot(contains('package:intl')));
      expect(
        generated(_cards, formatPluralNumbers: true),
        contains('package:intl'),
      );
    });

    test('one formatter is shared by every # in a locale', () {
      final source = generated({
        'en.json': '''
{
  "cards": "{count, plural, one{# card} other{# cards}}",
  "files": "{count, plural, one{# file} other{# files}}"
}
''',
      }, formatPluralNumbers: true);
      expect(
        source.split('_enNumberDecimalPattern =').length - 1,
        1,
        reason: 'the formatter should be declared once',
      );
    });

    test('# after an offset formats the adjusted value', () {
      final source = generated({
        'en.json':
            '{"likes": "{count, plural, offset:1 '
            'one{You and # other} other{You and # others}}"}',
      }, formatPluralNumbers: true);
      expect(source, contains(r'final $countOffset = count - 1;'));
      expect(
        source,
        contains(
          r"return 'You and ${_enNumberDecimalPattern.format($countOffset)} "
          r"others';",
        ),
      );
    });

    test('# inside a selectordinal is formatted too', () {
      final source = generated({
        'en.json': '{"rank": "{place, selectordinal, other{#th}}"}',
      }, formatPluralNumbers: true);
      expect(
        source,
        contains(r"return '${_enNumberDecimalPattern.format(place)}th';"),
      );
    });

    test('each locale formats # with its own pattern', () {
      final result = runGenerator({
        'en.json': '{"cards": "{count, plural, one{# card} other{# cards}}"}',
        'ru.json':
            '{"cards": "{count, plural, one{# карта} '
            'few{# карты} many{# карт} other{# карты}}"}',
      }, configYaml: _config(formatPluralNumbers: true));

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains("NumberFormat.decimalPattern('en')"));
      expect(source, contains("NumberFormat.decimalPattern('ru')"));
      expect(source, contains('_ruNumberDecimalPattern.format(count)'));
    });

    test('an explicit {count, number} is unaffected by the flag', () {
      final withFlag = generated({
        'en.json': '{"total": "Total: {amount, number}"}',
      }, formatPluralNumbers: true);
      final without = generated({
        'en.json': '{"total": "Total: {amount, number}"}',
      });
      expect(withFlag, without);
    });

    test('a non boolean value is rejected', () {
      final result = runGenerator(
        _cards,
        configYaml: '''
base_locale: en
fallback_locale: en
format_plural_numbers: sometimes
flutter:
  enabled: false
''',
      );
      final diagnostic = result.diagnostics.first;
      expect(diagnostic.code, 'invalid_config');
      expect(diagnostic.message, contains('true or false'));
    });

    test('the key is known, so it raises no unknown_config_key warning', () {
      final result = runGenerator(
        _cards,
        configYaml: _config(formatPluralNumbers: true),
      );
      expect(codesOf(result), isNot(contains('unknown_config_key')));
    });

    test('output stays deterministic with the flag on', () {
      expect(
        generated(_cards, formatPluralNumbers: true),
        generated(_cards, formatPluralNumbers: true),
      );
    });
  });
}
