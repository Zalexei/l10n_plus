import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

String _config({bool fill = true}) =>
    '''
base_locale: en
fallback_locale: en
fill_missing_from_base: $fill
flutter:
  enabled: false
''';

GenerationResult _run(Map<String, String> translations, {bool fill = true}) =>
    runGenerator(translations, configYaml: _config(fill: fill));

const Map<String, String> _partial = {
  'en.json': '{"auth": {"title": "Log in", "subtitle": "Welcome"}}',
  'ru.json': '{"auth": {"title": "Войти"}}',
};

void main() {
  group('off by default', () {
    test('an untranslated key is still an error', () {
      final result = _run(_partial, fill: false);
      expect(errorsOf(result), ['missing_key']);
    });

    test('the error names the way out', () {
      final diagnostic = _run(_partial, fill: false).diagnostics.single;
      expect(diagnostic.details, contains('fill_missing_from_base'));
    });

    test('omitting the key entirely is the same as false', () {
      final withFalse = _run(_partial, fill: false);
      final without = runGenerator(
        _partial,
        configYaml: '''
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''',
      );
      expect(codesOf(without), codesOf(withFalse));
    });
  });

  group('on', () {
    test('generation succeeds, with a warning per untranslated key', () {
      final result = _run(_partial);

      expect(errorsOf(result), isEmpty);
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.code, 'missing_key');
      expect(diagnostic.severity, Severity.warning);
      expect(diagnostic.translationKey, 'auth.subtitle');
      expect(diagnostic.message, contains('not translated in ru'));
      expect(diagnostic.details, contains('render exactly as en'));
    });

    test('the untranslated message renders as the base locale', () {
      final source = _run(_partial).files.single.contents;
      // Two classes, one Russian title and two English subtitles: the base's
      // own, and the Russian class falling back to it.
      expect(source, contains("String get title => 'Войти';"));
      expect(
        RegExp("String get subtitle => 'Welcome';").allMatches(source).length,
        2,
      );
    });

    test('the generated member says it is untranslated', () {
      final source = _run(_partial).files.single.contents;
      expect(source, contains('/// Untranslated: renders as `en`.'));
      // Only on the fallback, not on the base locale's own member.
      expect(RegExp('Untranslated').allMatches(source).length, 1);
    });

    test('a translated key is untouched', () {
      final source = _run(_partial).files.single.contents;
      expect(
        source,
        isNot(contains("String get title => 'Log in';\n\n  /// Untranslated")),
      );
    });
  });

  group('what falls back is the whole message', () {
    test('a plural keeps the base locale CLDR rules', () {
      final source = _run({
        'en.json':
            '{"cards": "{count, plural, one{# card} other{# cards}}",'
            ' "hello": "Hello"}',
        'ru.json': '{"hello": "Привет"}',
      }).files.single.contents;

      // English has one/other. Russian has one/few/many/other, and emitting
      // English text under Russian rules would produce "2 card".
      expect(
        RegExp(r'\$operands\.i % 10').hasMatch(source),
        isFalse,
        reason: 'Russian plural rules must not be applied to English text',
      );
      expect(RegExp(r"return '\$count cards';").allMatches(source).length, 2);
    });

    test('a formatted number uses the base locale formatter', () {
      final source = _run({
        'en.json': '{"total": "Total: {amount, number}", "hello": "Hello"}',
        'ru.json': '{"hello": "Привет"}',
      }).files.single.contents;

      // The Russian class renders the English message, so it formats with the
      // English pattern — the message is English, and a "1 234,5" inside
      // English words would be a stranger result than leaving it alone.
      expect(source, contains('_enNumberDecimalPattern'));
      expect(source, isNot(contains('_ruNumberDecimalPattern')));
    });

    test('a select keeps the base locale branches', () {
      final result = _run({
        'en.json':
            '{"greet": "{gender, select, male{Mr} other{Mx}}", "hi": "Hi"}',
        'ru.json': '{"hi": "Привет"}',
      });

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains('enum GreetGender'));
      expect(RegExp('GreetGender.male =>').allMatches(source).length, 2);
    });

    test('a whole namespace may be untranslated', () {
      final result = _run({
        'en.json': '{"a": "A", "wallet": {"x": "X", "y": "Y"}}',
        'ru.json': '{"a": "А"}',
      });

      expect(errorsOf(result), isEmpty);
      // One warning for the group, not one per key inside it.
      expect(codesOf(result), ['missing_key']);
      final source = result.files.single.contents;
      expect(source, contains(r'$Wallet get wallet => const $WalletRu();'));
      expect(RegExp("String get x => 'X';").allMatches(source).length, 2);
    });
  });

  group('what it does not excuse', () {
    test('a key the base locale does not have is still an error', () {
      final result = _run({
        'en.json': '{"a": "A"}',
        'ru.json': '{"a": "А", "b": "Б"}',
      });
      expect(errorsOf(result), contains('extra_key'));
    });

    test('a translated key with the wrong arguments is still an error', () {
      final result = _run({
        'en.json': '{"a": "Hello, {name}"}',
        'ru.json': '{"a": "Привет"}',
      });
      expect(errorsOf(result), contains('missing_placeholder'));
    });

    test('the base locale itself may not be missing', () {
      final result = _run({'ru.json': '{"a": "А"}'});
      expect(errorsOf(result), contains('missing_base_locale'));
    });
  });

  test('output stays deterministic', () {
    expect(
      _run(_partial).files.single.contents,
      _run(_partial).files.single.contents,
    );
  });

  test('a non boolean value is rejected', () {
    final result = runGenerator(
      _partial,
      configYaml: '''
base_locale: en
fallback_locale: en
fill_missing_from_base: sometimes
flutter:
  enabled: false
''',
    );
    expect(result.diagnostics.first.code, 'invalid_config');
    expect(result.diagnostics.first.message, contains('true or false'));
  });

  group('coverage', () {
    const config = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
fill_missing_from_base: true
flutter:
  enabled: false
''';

    LocaleCoverage coverageOf(GenerationResult result, String locale) =>
        result.coverage.firstWhere((c) => c.locale == locale);

    test('counts messages, not the subtrees the warnings collapse to', () {
      // One warning names `b`; four messages are untranslated.
      final result = runGenerator({
        'en.json':
            '{"a": "A", "b": {"x": "X", "y": "Y", "z": {"q": "Q", "r": "R"}}}',
        'ru.json': '{"a": "А"}',
      }, configYaml: config);

      expect(errorsOf(result), isEmpty);
      final ru = coverageOf(result, 'ru');
      expect(ru.total, 5);
      expect(ru.translated, 1);
      expect(ru.untranslated, 4);
      expect(ru.percent, 20);
      expect(ru.isComplete, isFalse);
    });

    test('the base locale is complete by definition', () {
      final result = runGenerator({
        'en.json': '{"a": "A", "b": "B"}',
        'ru.json': '{"a": "А"}',
      }, configYaml: config);

      expect(coverageOf(result, 'en').isComplete, isTrue);
      expect(coverageOf(result, 'en').percent, 100);
    });

    test('every locale is listed, in locale order', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'de.json': '{"a": "A"}',
        'ru.json': '{"a": "А"}',
      }, configYaml: config);

      expect(result.coverage.map((c) => c.locale), ['de', 'en', 'ru']);
      expect(result.coverage.every((c) => c.isComplete), isTrue);
    });

    test('percent rounds down, so 99 percent never reads as done', () {
      final translations = {for (var i = 0; i < 200; i++) 'k$i': 'v$i'};
      final ru = Map<String, String>.from(translations)..remove('k0');
      final result = runGenerator({
        'en.json': _json(translations),
        'ru.json': _json(ru),
      }, configYaml: config);

      final coverage = result.coverage.firstWhere((c) => c.locale == 'ru');
      expect(coverage.translated, 199);
      expect(coverage.total, 200);
      expect(coverage.percent, 99);
      expect(coverage.isComplete, isFalse);
    });
  });
}

String _json(Map<String, String> entries) =>
    '{${entries.entries.map((e) => '"${e.key}": "${e.value}"').join(', ')}}';
