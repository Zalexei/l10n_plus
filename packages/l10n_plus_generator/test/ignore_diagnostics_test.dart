import 'package:l10n_plus_generator/src/diagnostic.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `ignore_diagnostics` turns off warnings a project has decided about.
///
/// At three thousand keys and ten locales, one plural written without a `few`
/// branch is two thousand identical warnings. A report that long is not read,
/// so the warnings that matter are lost with the ones that do not.
String _config(String? ignore) =>
    '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
${ignore ?? ''}
''';

/// A Russian plural that declares only `other`, which warns four times over:
/// `one`, `few` and `many` are all missing.
const Map<String, String> _incomplete = {
  'en.json': '{"n": "{count, plural, other{# items}}"}',
  'ru.json': '{"n": "{count, plural, other{# штук}}"}',
};

void main() {
  group('configuration', () {
    test('accepts a list of warning codes', () {
      final result = runGenerator(
        _incomplete,
        configYaml: _config(
          'ignore_diagnostics: [missing_plural_category, '
          'unused_plural_category]',
        ),
      );
      expect(codesOf(result), isEmpty);
    });

    test('an unknown code is reported rather than accepted', () {
      final result = runGenerator(
        _incomplete,
        configYaml: _config('ignore_diagnostics: [missing_plural_categories]'),
      );

      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'invalid_config',
      );
      expect(diagnostic.severity, Severity.warning);
      expect(diagnostic.message, contains('Unknown diagnostic code'));
      expect(diagnostic.details, contains('missing_plural_category'));
      // The entry silenced nothing, so the warnings are still there.
      expect(codesOf(result), contains('missing_plural_category'));
    });

    test('an error code cannot be silenced', () {
      final result = runGenerator({
        'en.json': '{"a": "A"}',
        'ru.json': '{"a": "А", "b": "Б"}',
      }, configYaml: _config('ignore_diagnostics: [extra_key, invalid_json]'));

      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'invalid_config' && d.message.contains('invalid_json'),
      );
      expect(diagnostic.severity, Severity.warning);
      expect(diagnostic.message, contains('is an error and cannot be ignored'));
      // `extra_key` is accepted by the config — it is a warning under
      // `extra_keys: warn` — but it is an error here, so it still shows.
      expect(errorsOf(result), contains('extra_key'));
    });

    test('a scalar instead of a list is reported', () {
      final result = runGenerator(
        _incomplete,
        configYaml: _config('ignore_diagnostics: missing_plural_category'),
      );

      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'invalid_config',
      );
      expect(diagnostic.message, contains('must be a list'));
      expect(codesOf(result), contains('missing_plural_category'));
    });

    test('a non string entry is reported and the rest still apply', () {
      final result = runGenerator(
        _incomplete,
        configYaml: _config('ignore_diagnostics: [7, missing_plural_category]'),
      );

      expect(
        result.diagnostics.where((d) => d.code == 'invalid_config'),
        hasLength(1),
      );
      expect(codesOf(result), isNot(contains('missing_plural_category')));
    });
  });

  group('filtering', () {
    test('the warnings are gone, and are counted', () {
      final noisy = runGenerator(_incomplete, configYaml: _config(null));
      expect(codesOf(noisy), contains('missing_plural_category'));
      expect(noisy.ignoredCount, 0);

      final quiet = runGenerator(
        _incomplete,
        configYaml: _config('ignore_diagnostics: [missing_plural_category]'),
      );
      expect(codesOf(quiet), isEmpty);
      // Counted rather than merely dropped: the CLI says how much of the
      // report a project is choosing not to see.
      expect(quiet.ignoredCount, greaterThan(0));
    });

    test('ignoring one code leaves the others alone', () {
      final result = runGenerator({
        'en.json': '{"n": "{count, plural, one{# item} other{# items}}"}',
        'ru.json': '{"n": "{count, plural, other{# штук}}"}',
        'ja.json': '{"n": "{count, plural, one{#} other{#}}"}',
      }, configYaml: _config('ignore_diagnostics: [unused_plural_category]'));

      expect(codesOf(result), contains('missing_plural_category'));
      expect(codesOf(result), isNot(contains('unused_plural_category')));
    });

    test('generation still succeeds and writes the same file', () {
      final noisy = runGenerator(_incomplete, configYaml: _config(null));
      final quiet = runGenerator(
        _incomplete,
        configYaml: _config('ignore_diagnostics: [missing_plural_category]'),
      );
      // Silencing a warning changes the report, never the output.
      expect(quiet.files.single.contents, noisy.files.single.contents);
    });
  });

  group('the collector itself', () {
    test('never drops an error, whatever the list says', () {
      // `missing_key` is a warning under `fill_missing_from_base` and an error
      // without it, so the same code arrives at both severities.
      final collector = DiagnosticCollector(ignoredCodes: {'missing_key'})
        ..add(const Diagnostic.warning(code: 'missing_key', message: 'w'))
        ..add(const Diagnostic.error(code: 'missing_key', message: 'e'));

      expect(collector.diagnostics, hasLength(1));
      expect(collector.diagnostics.single.severity, Severity.error);
      expect(collector.ignoredCount, 1);
    });
  });

  group('the code registry', () {
    test('lists every code the generator can report', () {
      // A code missing from the registry is a code no project can configure,
      // and `ignore_diagnostics` would call it a typo. The check is textual
      // because some codes are chosen by an expression rather than written as
      // a literal at the call site.
      final missing = <String>[];
      for (final code in _codesInSource()) {
        if (!DiagnosticCodes.all.contains(code)) missing.add(code);
      }
      expect(
        missing,
        isEmpty,
        reason:
            'Add these to DiagnosticCodes:\n'
            '${missing.join('\n')}',
      );
    });

    test('no code is both always an error and suppressible', () {
      expect(
        DiagnosticCodes.alwaysErrors.intersection(DiagnosticCodes.suppressible),
        isEmpty,
      );
    });
  });
}

/// Every diagnostic code literal in the generator's own sources.
///
/// Read from `code:` to the `message:` that always follows it, rather than
/// with one expression: a couple of sites choose the code with a conditional,
/// and matching conditionals anywhere would pick up unrelated strings.
Set<String> _codesInSource() {
  final codes = <String>{};
  final literal = RegExp(r"'([a-z][a-z_]*)'");
  for (final file in libSources()) {
    for (final match in 'code:'.allMatches(file)) {
      final stop = file.indexOf('message:', match.end);
      if (stop == -1) continue;
      for (final code in literal.allMatches(file.substring(match.end, stop))) {
        codes.add(code.group(1)!);
      }
    }
  }
  return codes;
}
