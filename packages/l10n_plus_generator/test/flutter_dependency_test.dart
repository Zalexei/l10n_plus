import 'package:test/test.dart';

import 'support/fixture.dart';

/// `flutter.enabled` defaults to on, so the configuration that the CLI
/// suggests to a newcomer generates the Flutter glue in a Dart project too.
/// The glue imports `package:flutter` and `package:l10n_plus_flutter`, so
/// without them it is a screen of analyzer errors in a file nobody wrote.
const String _glueOn = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
flutter:
  enabled: true
''';

const String _glueOff = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
flutter:
  enabled: false
''';

const Map<String, String> _translations = {'en.json': '{"a": "ok"}'};

void main() {
  group('the Flutter glue needs Flutter', () {
    test('a Dart project is warned, and told how to turn the glue off', () {
      final result = runGenerator(
        _translations,
        configYaml: _glueOn,
        pubspec: '''
name: demo
environment:
  sdk: ^3.9.0
dependencies:
  l10n_plus: any
''',
      );

      final warning = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_flutter_dependency',
      );
      expect(warning.message, contains('flutter or l10n_plus_flutter'));
      expect(warning.details, contains('enabled: false'));
    });

    test('only what is missing is named', () {
      final result = runGenerator(
        _translations,
        configYaml: _glueOn,
        pubspec: '''
name: demo
dependencies:
  flutter:
    sdk: flutter
''',
      );

      final warning = result.diagnostics.singleWhere(
        (d) => d.code == 'missing_flutter_dependency',
      );
      expect(warning.message, contains('l10n_plus_flutter'));
      expect(warning.message, isNot(contains('flutter or')));
    });

    test('no warning for a Flutter project', () {
      final result = runGenerator(
        _translations,
        configYaml: _glueOn,
        pubspec: '''
name: demo
dependencies:
  flutter:
    sdk: flutter
  l10n_plus_flutter: any
''',
      );

      expect(codesOf(result), isNot(contains('missing_flutter_dependency')));
    });

    test('no warning when the glue is off', () {
      final result = runGenerator(
        _translations,
        configYaml: _glueOff,
        pubspec: '''
name: demo
dependencies:
  l10n_plus: any
''',
      );

      expect(codesOf(result), isNot(contains('missing_flutter_dependency')));
    });
  });
}
