@TestOn('vm')
library;

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:l10n_plus_generator/src/diagnostic.dart' show DiagnosticCodes;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `bidi_isolation`: where the isolates go, and where they deliberately do not.
///
/// What they *do* is a fact about text layout, which this file cannot assert —
/// that is `packages/l10n_plus_flutter/test/bidi_isolation_test.dart`, which
/// lays the strings out and reads the positions back. Here the question is
/// only whether the emitter put them around the right things.
const String _plain = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
flutter:
  enabled: false
''';

const String _on = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
bidi_isolation: true
flutter:
  enabled: false
''';

const String _overrides = '${_plain}runtime_overrides: true\n';
const String _onWithOverrides = '${_on}runtime_overrides: true\n';

/// A Hebrew project, for the warning about having the option off.
String _hebrew({bool isolation = false}) =>
    'input_directory: translations\n'
    'output_directory: lib/generated\n'
    'base_locale: he\n'
    'fallback_locale: he\n'
    'class_name: AppLocalizations\n'
    'locale_enum_name: AppLocale\n'
    '${isolation ? 'bidi_isolation: true\n' : ''}'
    'flutter:\n'
    '  enabled: false\n';

String _source(GenerationResult result) {
  expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));
  return result.files.single.contents;
}

void main() {
  // The escapes as the emitter writes them, assembled here so that this file
  // carries no direction control of its own.
  final fsi =
      r'\u{'
      '2068}';
  final pdi =
      r'\u{'
      '2069}';

  group('where the isolates go', () {
    test('nowhere, with the option off', () {
      final source = _source(
        runGenerator({'en.json': '{"a": "Hi {name}"}'}, configYaml: _plain),
      );
      expect(
        source,
        contains(r"String a({required String name}) => 'Hi $name';"),
      );
      expect(source, isNot(contains(r'\u{20')));
    });

    test('around a value that sits in text', () {
      expect(
        _source(
          runGenerator({'en.json': '{"a": "Hi {name}"}'}, configYaml: _on),
        ),
        contains("String a({required String name}) => 'Hi $fsi\$name$pdi';"),
      );
    });

    test('not around a message that is nothing but the value', () {
      // There is no text in this string for the value to be reordered
      // against, the widget's own direction decides the line, and leaving it
      // alone keeps the `String` passthrough an allocation free getter.
      expect(
        _source(runGenerator({'en.json': '{"a": "{name}"}'}, configYaml: _on)),
        contains('String a({required String name}) => name;'),
      );
    });

    test('but around the same value alone in a rich span', () {
      // A rich message is one paragraph assembled from several strings, so the
      // text this value could be reordered against is in its siblings.
      expect(
        _source(
          runGenerator({
            'en.json': '{"a(rich)": "Read <b>{name}</b> now"}',
          }, configYaml: _on),
        ),
        contains("L10nTagSpan('b', [L10nTextSpan('$fsi\$name$pdi')])"),
      );
    });

    test('around what formats a value, not inside it', () {
      final source = _source(
        runGenerator({'en.json': '{"a": "x {n, number} y"}'}, configYaml: _on),
      );
      expect(source, contains("'x $fsi\${_en"));
      expect(source, contains(".format(n)}$pdi y'"));
    });

    test('around the plural count, and not around a nested choice', () {
      final source = _source(
        runGenerator({
          'en.json':
              '{"a": "You have {n, plural, one{# card} other{# cards}} left"}',
        }, configYaml: _on),
      );
      // The count is a value too, and its rendering can carry a sign or a
      // percent — which is one of the cases measured in the Flutter test.
      expect(source, contains("return '$fsi\$n$pdi cards';"));
      // The choice renders this locale's own words in this locale's own
      // direction, and whatever value sits inside it was isolated there.
      expect(source, contains(r"=> 'You have ${_a$0(n: n)} left';"));
    });

    test('around the values an override is filled with', () {
      // Not around the override's text, which the bundle writes: around the
      // values substituted into it. So a bundle that reworded the sentence
      // around a value gets the isolates without knowing they exist — and a
      // message that is bare today is isolated on the override path, because
      // an override may put words around it.
      final source = _source(
        runGenerator({
          'en.json': '{"a": "{name}"}',
        }, configYaml: _onWithOverrides),
      );
      expect(source, contains("{'name': '$fsi\$name$pdi'}"));
    });

    test('and nothing about the overridable surface changes', () {
      // The option changes literals and the values handed to `fill`, never a
      // key, a branch or a token name. So turning it on does not invalidate a
      // bundle anybody has already stamped.
      const project = {
        'en.json':
            '{"a": "Hi {name}", "b": "{n, plural, one{# x} other{# xs}}"}',
      };
      String fingerprint(String configYaml) {
        final result = runGenerator(project, configYaml: configYaml);
        return OverrideFingerprint.of(result.overrides.forLocale('en')!);
      }

      expect(fingerprint(_onWithOverrides), fingerprint(_overrides));
    });
  });

  group('the warning about having it off', () {
    const hebrew = {'he.json': '{"a": "שלום {name} בוקר"}'};

    test('names the locale, what goes wrong, and both ways out', () {
      final result = runGenerator(hebrew, configYaml: _hebrew());
      expect(codesOf(result), contains('bidi_isolation_off'));
      final report = result.diagnostics.firstWhere(
        (d) => d.code == 'bidi_isolation_off',
      );
      expect(report.severity, Severity.warning);
      expect(report.message, contains('he'));
      expect(report.details, contains('bidi_isolation: true'));
      expect(report.details, contains('ignore_diagnostics'));
    });

    test('is silent once the option is on', () {
      expect(
        codesOf(runGenerator(hebrew, configYaml: _hebrew(isolation: true))),
        isNot(contains('bidi_isolation_off')),
      );
    });

    test('is silent for a project written left to right', () {
      expect(
        codesOf(
          runGenerator({'en.json': '{"a": "Hi {name}"}'}, configYaml: _plain),
        ),
        isNot(contains('bidi_isolation_off')),
      );
    });

    test('is silent when there is no value to isolate', () {
      // The hazard needs a value and a direction to disagree about.
      expect(
        codesOf(
          runGenerator({'he.json': '{"a": "שלום"}'}, configYaml: _hebrew()),
        ),
        isNot(contains('bidi_isolation_off')),
      );
    });

    test('is silent for a select, whose value never reaches the string', () {
      expect(
        codesOf(
          runGenerator({
            'he.json': '{"a": "{t, select, f{רשמי} other{הי}}"}',
          }, configYaml: _hebrew()),
        ),
        isNot(contains('bidi_isolation_off')),
      );
    });

    test('can be silenced, unlike the errors', () {
      expect(DiagnosticCodes.suppressible, contains('bidi_isolation_off'));
      expect(
        codesOf(
          runGenerator(
            hebrew,
            configYaml:
                '${_hebrew()}ignore_diagnostics: [bidi_isolation_off]\n',
          ),
        ),
        isNot(contains('bidi_isolation_off')),
      );
    });
  });
}
