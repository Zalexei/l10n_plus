import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `fill_missing_from_base` into a locale that reads the other way round.
///
/// The combination ships English sentences in an Arabic build and nothing
/// about the generated code says so: the member exists, returns a complete
/// sentence and renders without an error. `missing_key` already reports each
/// key, but that is the warning a team accepted when it turned the option on,
/// so it is the one it has stopped reading.
String _config({bool fill = true, String? extra}) =>
    '''
base_locale: en
fallback_locale: en
fill_missing_from_base: $fill
flutter:
  enabled: false
${extra ?? ''}
''';

GenerationResult _run(
  Map<String, String> translations, {
  bool fill = true,
  String? extra,
}) => runGenerator(
  translations,
  configYaml: _config(fill: fill, extra: extra),
);

/// An English base locale, a complete Russian locale and a half done Arabic
/// one: `auth.subtitle` and the two keys under `wallet` are untranslated.
const Map<String, String> _partial = {
  'en.json':
      '{"auth": {"title": "Log in", "subtitle": "Welcome"},'
      ' "wallet": {"balance": "Balance", "history": "History"}}',
  'ar.json': '{"auth": {"title": "تسجيل الدخول"}}',
  'ru.json':
      '{"auth": {"title": "Войти", "subtitle": "Добро пожаловать"},'
      ' "wallet": {"balance": "Баланс", "history": "История"}}',
};

Diagnostic _direction(GenerationResult result) =>
    result.diagnostics.singleWhere((d) => d.code == 'fill_direction_mismatch');

void main() {
  group('a right-to-left locale filled from a left-to-right base', () {
    test('warns once, naming the locale, the count and the base', () {
      final result = _run(_partial);

      expect(errorsOf(result), isEmpty);
      expect(
        codesOf(result).where((c) => c == 'fill_direction_mismatch'),
        hasLength(1),
      );
      final diagnostic = _direction(result);
      expect(diagnostic.severity, Severity.warning);
      expect(
        diagnostic.message,
        'ar is right-to-left, but 3 messages fall back to left-to-right en '
        'text.',
      );
    });

    test('the count is messages, not the findings they collapse into', () {
      // Two warnings — `auth.subtitle` and the whole `wallet` group — stand
      // for three messages, and three is what reaches the screen.
      final result = _run(_partial);
      expect(
        codesOf(result).where((c) => c == 'missing_key'),
        hasLength(2),
        reason: 'the untranslated namespace collapses into one finding',
      );
      expect(_direction(result).message, contains('3 messages'));
    });

    test('one untranslated message reads as one message', () {
      final result = _run({
        'en.json': '{"a": "A", "b": "B"}',
        'ar.json': '{"a": "أ"}',
      });
      expect(_direction(result).message, contains('1 message falls back'));
    });

    test('the details say why this is worse than a missing translation', () {
      final details = _direction(_run(_partial)).details!;

      expect(details, contains('also reported as missing_key'));
      expect(details, contains('looks finished'));
      expect(details, contains('wrong way round'));
      // And what to do about it, in both directions.
      expect(details, contains('"fill_missing_from_base: false"'));
      expect(
        details,
        contains('ignore_diagnostics: [fill_direction_mismatch]'),
      );
    });

    test('it points at the locale, not at one key', () {
      final diagnostic = _direction(_run(_partial));
      expect(diagnostic.translationKey, isNull);
      expect(diagnostic.span!.sourceUrl!.path, endsWith('ar.json'));
    });

    test('the fill itself still happens', () {
      // The warning is about what was generated, so the English text must be
      // in there — otherwise it is warning about nothing.
      final source = _run(_partial).files.single.contents;
      expect(source, contains("String get title => 'تسجيل الدخول';"));
      expect(
        RegExp("String get balance => 'Balance';").allMatches(source),
        hasLength(2),
      );
    });
  });

  group('when it stays silent', () {
    test('two left-to-right locales', () {
      final result = _run({
        'en.json': '{"a": "A", "b": "B"}',
        'ru.json': '{"a": "А"}',
      });

      expect(codesOf(result), ['missing_key']);
      expect(codesOf(result), isNot(contains('fill_direction_mismatch')));
    });

    test('two right-to-left locales', () {
      // Hebrew filled from Arabic is a wrong language but a right layout, so
      // there is nothing here that `missing_key` has not already said.
      final result = runGenerator(
        {'ar.json': '{"a": "أ", "b": "ب"}', 'he.json': '{"a": "א"}'},
        configYaml: '''
base_locale: ar
fallback_locale: ar
fill_missing_from_base: true
flutter:
  enabled: false
''',
      );

      expect(codesOf(result), ['missing_key']);
    });

    test('a complete right-to-left locale, with nothing filled', () {
      final result = _run({'en.json': '{"a": "A"}', 'ar.json': '{"a": "أ"}'});
      expect(codesOf(result), isEmpty);
    });

    test('the fill option is off, so nothing falls back at all', () {
      // Without the option the untranslated keys are errors and no base text
      // is substituted, so the direction never comes into it.
      final result = _run(_partial, fill: false);

      expect(errorsOf(result), everyElement('missing_key'));
      expect(codesOf(result), isNot(contains('fill_direction_mismatch')));
    });
  });

  test('a right-to-left base locale warns about its left-to-right locales', () {
    // Symmetric: the problem is that the two directions differ, not that
    // Arabic is one of them.
    final result = runGenerator(
      {'ar.json': '{"a": "أ", "b": "ب"}', 'en.json': '{"a": "A"}'},
      configYaml: '''
base_locale: ar
fallback_locale: ar
fill_missing_from_base: true
flutter:
  enabled: false
''',
    );

    expect(
      _direction(result).message,
      'en is left-to-right, but 1 message falls back to right-to-left ar '
      'text.',
    );
  });

  test('each locale gets its own warning', () {
    final result = _run({
      'en.json': '{"a": "A", "b": "B", "c": "C"}',
      'ar.json': '{"a": "أ"}',
      'he.json': '{"a": "א", "b": "ב"}',
    });

    final messages = result.diagnostics
        .where((d) => d.code == 'fill_direction_mismatch')
        .map((d) => d.message)
        .toList();
    expect(messages, hasLength(2));
    expect(
      messages.any((m) => m.startsWith('ar is') && m.contains('2 ')),
      isTrue,
    );
    expect(
      messages.any((m) => m.startsWith('he is') && m.contains('1 ')),
      isTrue,
    );
  });

  test('it is suppressible through ignore_diagnostics', () {
    final result = _run(
      _partial,
      extra: 'ignore_diagnostics: [fill_direction_mismatch]',
    );

    expect(codesOf(result), isNot(contains('fill_direction_mismatch')));
    // The keys are still reported; only the direction warning is silenced.
    expect(codesOf(result), contains('missing_key'));
    expect(result.ignoredCount, 1);
  });

  test('the code is registered, so ignore_diagnostics accepts it', () {
    // A code the registry does not know is reported as a typo instead of
    // silencing anything.
    final result = _run(
      _partial,
      extra: 'ignore_diagnostics: [fill_direction_mismatch]',
    );
    expect(codesOf(result), isNot(contains('invalid_config')));
  });

  test('a renamed key counts as filled, because it is', () {
    // `_renameIn` replaces the missing/extra pair with one `renamed_key`
    // finding, but the key is still absent under its new name, so base text
    // is substituted for it all the same.
    final result = _run({
      'en.json': '{"a": "A", "subtitle": "Welcome"}',
      'ar.json': '{"a": "أ", "subtitel": "مرحبا"}',
    });

    expect(codesOf(result), contains('renamed_key'));
    expect(_direction(result).message, contains('1 message falls back'));
  });
}
