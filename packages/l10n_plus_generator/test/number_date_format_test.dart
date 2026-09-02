import 'package:l10n_plus_generator/src/ast/message_ast.dart';
import 'package:l10n_plus_generator/src/codegen/intl_formatters.dart';
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
  group('number formatting', () {
    test('a plain number argument uses the decimal pattern', () {
      final source = generated({
        'en.json': '{"total": "Total: {amount, number}"}',
      });
      expect(source, contains("NumberFormat.decimalPattern('en')"));
      expect(source, contains(r'${_enNumberDecimalPattern.format(amount)}'));
      expect(source, contains('String total({required num amount})'));
    });

    test('styles map onto their intl constructors', () {
      final source = generated({
        'en.json': '''
{
  "percent": "{value, number, percent}",
  "money": "{value2, number, currency}",
  "compact": "{value3, number, compact}"
}
''',
      });
      expect(source, contains("NumberFormat.percentPattern('en')"));
      expect(source, contains("NumberFormat.currency(locale: 'en')"));
      expect(source, contains("NumberFormat.compact(locale: 'en')"));
    });

    test('an unknown style is rejected with the list of valid ones', () {
      final result = runGenerator({
        'en.json': '{"a": "{n, number, gazillions}"}',
      }, configYaml: _config);

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'icu_invalid_style');
      expect(diagnostic.message, contains('gazillions'));
      expect(diagnostic.details, contains('percent'));
    });
  });

  group('date and time formatting', () {
    test('a date skeleton on a time style is rejected', () {
      final result = runGenerator({
        'en.json': '{"a": "{t, time, yMMMd}"}',
      }, configYaml: _config);

      // It would have compiled and rendered a date, ignoring the time.
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'icu_invalid_style');
      expect(diagnostic.message, contains('yMMMd'));
      expect(diagnostic.details, contains('jms'));
      expect(diagnostic.details, isNot(contains('yMMMd')));
    });

    test('clock skeletons still work on both date and time', () {
      final source = generated({
        'en.json': '{"a": "{t, time, jm}", "b": "{d, date, Hms}"}',
      });
      expect(source, contains("DateFormat.jm('en')"));
      expect(source, contains("DateFormat.Hms('en')"));
    });

    test('named styles and skeletons both work', () {
      final source = generated({
        'en.json': '''
{
  "short": "{d, date, short}",
  "skeleton": "{d2, date, yMMMEd}",
  "clock": "{t, time}"
}
''',
      });
      expect(source, contains("DateFormat.yMd('en')"));
      expect(source, contains("DateFormat.yMMMEd('en')"));
      expect(source, contains("DateFormat.jm('en')"));
      expect(source, contains('String short({required DateTime d})'));
    });

    test('one argument may be both a date and a time', () {
      final source = generated({
        'en.json': '{"a": "On {d, date, short} at {d, time}"}',
      });
      expect(source, contains('String a({required DateTime d})'));
      expect(source, contains(r'${_enDateYMd.format(d)}'));
      expect(source, contains(r'${_enDateJm.format(d)}'));
    });

    test('a number and a date argument with one name is an error', () {
      final result = runGenerator({
        'en.json': '{"a": "{x, number} {x, date, short}"}',
      }, configYaml: _config);
      expect(errorsOf(result), contains('argument_kind_conflict'));
    });
  });

  group('formatters are shared and locale specific', () {
    test('one final per locale and style, reused across messages', () {
      final source = generated({
        'en.json': '{"a": "{x, number}", "b": "{y, number}"}',
        'ru.json': '{"a": "{x, number}", "b": "{y, number}"}',
      });
      expect(
        RegExp('_enNumberDecimalPattern =').allMatches(source),
        hasLength(1),
      );
      expect(source, contains("NumberFormat.decimalPattern('ru')"));
      // A message that is nothing but one argument needs no interpolation.
      expect(source, contains('_ruNumberDecimalPattern.format(x)'));
    });

    test('a region is passed through to intl', () {
      final source = generated({
        'en.json': '{"a": "{x, number}"}',
        'pt_BR.json': '{"a": "{x, number}"}',
      });
      expect(source, contains('_ptBrNumberDecimalPattern'));
      expect(source, contains("'pt-BR'"));
    });
  });

  group('imports', () {
    test('intl is imported only when something formats', () {
      expect(
        generated({'en.json': '{"a": "plain"}'}),
        isNot(contains('package:intl')),
      );
      expect(
        generated({'en.json': '{"a": "{x, number}"}'}),
        contains("import 'package:intl/intl.dart';"),
      );
    });

    test('a missing intl dependency is reported', () {
      final result = runGenerator(
        {'en.json': '{"a": "{x, number}"}'},
        configYaml: _config,
        pubspec: '''
name: demo
environment:
  sdk: ^3.9.0
dependencies:
  l10n_plus: any
''',
      );
      final warning = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_intl_dependency',
      );
      expect(warning.details, contains('intl: any'));
    });

    test('no warning when intl is already a dependency', () {
      final result = runGenerator(
        {'en.json': '{"a": "{x, number}"}'},
        configYaml: _config,
        pubspec: '''
name: demo
dependencies:
  intl: ^0.19.0
''',
      );
      expect(codesOf(result), isNot(contains('missing_intl_dependency')));
    });
  });

  group('cross locale consistency', () {
    test('a differently formatted argument is a warning, not an error', () {
      final result = runGenerator({
        'en.json': '{"a": "{x, number, percent}"}',
        'ru.json': '{"a": "{x, number}"}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      final warning = result.diagnostics.singleWhere(
        (d) => d.code == 'format_style_mismatch',
      );
      expect(warning.details, contains('number, percent'));
    });

    test('a plain argument where the base formats is an error', () {
      final result = runGenerator({
        'en.json': '{"a": "{d, date, short}"}',
        'ru.json': '{"a": "{d}"}',
      }, configYaml: _config);
      expect(errorsOf(result), ['argument_kind_mismatch']);
    });
  });

  group('ARB format attribute', () {
    test('drives formatting for a plainly written placeholder', () {
      final source = generated({
        'en.arb':
            '{"@@locale": "en", "at": "At {when}", '
            '"@at": {"placeholders": '
            '{"when": {"type": "DateTime", "format": "yMMMd"}}}}',
      });
      expect(source, contains('String at({required DateTime when})'));
      expect(source, contains("DateFormat.yMMMd('en')"));
    });

    test('drives number formatting too', () {
      final source = generated({
        'en.arb':
            '{"@@locale": "en", "p": "{ratio}", '
            '"@p": {"placeholders": '
            '{"ratio": {"type": "double", "format": "percent"}}}}',
      });
      // The declared type is kept: `{ratio, number, percent}` written in the
      // message would generate `double` too.
      expect(source, contains('String p({required double ratio})'));
      expect(source, contains("NumberFormat.percentPattern('en')"));
    });

    test('an unknown format attribute is rejected', () {
      final result = runGenerator({
        'en.arb':
            '{"@@locale": "en", "at": "At {when}", '
            '"@at": {"placeholders": '
            '{"when": {"type": "DateTime", "format": "nonsense"}}}}',
      }, configYaml: _config);

      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'unsupported_placeholder_format');
      expect(diagnostic.details, contains('yMMMd'));
    });
  });

  test('the style allowlists stay in sync with the constructors used', () {
    for (final kind in ArgumentFormatKind.values) {
      for (final style in IntlFormatters.supportedStyles(kind)) {
        final binding = IntlFormatters.bindingFor(
          format: ArgumentFormat(kind, style),
          localeTag: 'en',
          localeDartName: 'en',
        );
        expect(binding, isNotNull, reason: '$kind $style');
        expect(binding!.initializer, contains("'en'"));
      }
    }
  });
}
