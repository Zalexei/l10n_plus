import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

const String _config = '''
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

GenerationResult _run(String yaml, {String name = 'en.yaml'}) =>
    runGenerator({name: yaml}, configYaml: _config);

String _generated(String yaml) {
  final result = _run(yaml);
  expect(
    errorsOf(result),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format(highlight: false)).join(),
  );
  return result.files.single.contents;
}

/// The one finding of [result], ignoring the cascade that follows it.
///
/// A file that is skipped leaves nothing to generate from, so
/// `no_translation_files` trails almost every parser diagnostic here. It is a
/// consequence, not a second finding.
Diagnostic _onlyDiagnostic(GenerationResult result) {
  final findings = result.diagnostics
      .where((d) => d.code != 'no_translation_files')
      .toList();
  expect(
    findings,
    hasLength(1),
    reason: result.diagnostics.map((d) => d.format(highlight: false)).join(),
  );
  return findings.single;
}

void main() {
  _unquotedBraceHint();
  group('shape', () {
    test('nested maps become namespaces', () {
      final source = _generated('''
auth:
  login:
    title: Log in
wallet:
  balance: Balance
''');
      expect(source, contains(r'$AuthLogin get login'));
      expect(source, contains("String get title => 'Log in';"));
      expect(source, contains("String get balance => 'Balance';"));
    });

    test('both .yaml and .yml are read', () {
      final result = runGenerator({'en.yml': 'a: A'}, configYaml: _config);
      expect(errorsOf(result), isEmpty);
      expect(result.files.single.contents, contains("String get a => 'A';"));
    });

    test('a YAML locale sits beside JSON and ARB in one project', () {
      final result = runGenerator({
        'en.yaml': 'greeting: Hello',
        'ru.json': '{"greeting": "Привет"}',
        'fr.arb': '{"@@locale": "fr", "greeting": "Bonjour"}',
      }, configYaml: _config);

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains("String get greeting => 'Hello';"));
      expect(source, contains("String get greeting => 'Привет';"));
      expect(source, contains("String get greeting => 'Bonjour';"));
    });

    test('the path names the locale, as it does for JSON', () {
      final diagnostic = _onlyDiagnostic(_run('a: A', name: 'notes.yaml'));
      expect(diagnostic.code, 'unrecognized_file_name');
      expect(diagnostic.message, contains('nowhere to declare a locale'));
      // Reported before the parser is asked to read it, so the message can
      // name the pattern the path failed to match.
      expect(diagnostic.details, contains('{locale}'));
    });
  });

  group('what YAML gets wrong that JSON cannot', () {
    test('a bare "true" is a boolean, and says so', () {
      // The reason this parser needs its own diagnostics: a perfectly
      // reasonable translation that YAML quietly turns into `true`.
      final diagnostic = _onlyDiagnostic(_run('confirm: true'));
      expect(diagnostic.code, 'invalid_leaf_type');
      expect(diagnostic.translationKey, 'confirm');
      expect(diagnostic.details, contains('a boolean'));
      expect(diagnostic.details, contains('quote it'));
    });

    test('quoting it fixes it', () {
      expect(
        _generated("confirm: 'true'"),
        contains("String get confirm => 'true';"),
      );
    });

    for (final word in ['false', 'null', '~', '5', '5.0', '.inf']) {
      test('"$word" is caught the same way', () {
        expect(errorsOf(_run('a: $word')), ['invalid_leaf_type']);
      });
    }

    for (final word in ['yes', 'no', 'on', 'off', '2026-01-01']) {
      test('"$word" is still a string, because this is YAML 1.2', () {
        // YAML 1.1 read these as booleans and dates. Rejecting them would be
        // rejecting valid translations.
        expect(errorsOf(_run('a: $word')), isEmpty);
      });
    }

    test('a number is not a translation either', () {
      final diagnostic = _onlyDiagnostic(_run('count: 5'));
      expect(diagnostic.code, 'invalid_leaf_type');
      expect(diagnostic.details, contains('an integer'));
    });

    test('a list is not a translation', () {
      final diagnostic = _onlyDiagnostic(_run('a:\n  - one\n  - two\n'));
      expect(diagnostic.code, 'invalid_leaf_type');
      expect(diagnostic.details, contains('a list'));
    });

    test('a non string key is rejected', () {
      final diagnostic = _onlyDiagnostic(_run('1: hello'));
      expect(diagnostic.code, 'invalid_key');
      expect(diagnostic.details, contains('an integer'));
    });
  });

  group('failure', () {
    test('malformed YAML is a diagnostic, not a crash', () {
      final diagnostic = _onlyDiagnostic(_run('a: [1, 2\nb: 3\n'));
      expect(diagnostic.code, 'invalid_yaml');
      expect(diagnostic.severity, Severity.error);
    });

    test('a duplicate key is reported by the YAML parser itself', () {
      final diagnostic = _onlyDiagnostic(_run('a: one\na: two\n'));
      expect(diagnostic.code, 'invalid_yaml');
      expect(diagnostic.message, contains('uplicate'));
    });

    test('a root that is not a map is rejected', () {
      final diagnostic = _onlyDiagnostic(_run('- one\n- two\n'));
      expect(diagnostic.code, 'invalid_root');
    });

    test('an empty key is rejected', () {
      final diagnostic = _onlyDiagnostic(_run("'': A"));
      expect(diagnostic.code, 'empty_key');
    });
  });

  group('spans point inside the message', () {
    /// The column an ICU diagnostic lands on, 1 based.
    int columnOf(String yaml) {
      final result = _run(yaml);
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code.startsWith('icu_'),
      );
      return diagnostic.span!.start.column + 1;
    }

    test('a plain scalar', () {
      // `a: {n, number, gazillions}` cannot be plain — it starts with `{` —
      // so use a message where the error is not at the start.
      expect(columnOf('a: Total {n, number, gazillions}'), 22);
    });

    test('a single quoted scalar', () {
      expect(columnOf("a: 'Total {n, number, gazillions}'"), 23);
    });

    test('a double quoted scalar', () {
      expect(columnOf('a: "Total {n, number, gazillions}"'), 23);
    });

    test('a scalar with escapes falls back to the whole value', () {
      // The offsets no longer line up character for character, so pointing
      // precisely would point wrongly. The span covers the value instead.
      final result = _run(r'a: "Total\t{n, number, gazillions}"');
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code.startsWith('icu_'),
      );
      expect(diagnostic.span!.text, startsWith('"Total'));
    });

    test('a block scalar still parses, with a whole value span', () {
      final result = _run('a: >-\n  Total {n, number, gazillions}\n');
      final diagnostic = result.diagnostics.singleWhere(
        (d) => d.code.startsWith('icu_'),
      );
      expect(diagnostic.code, 'icu_invalid_style');
    });

    test('a valid block scalar generates the folded text', () {
      expect(
        _generated('a: >-\n  one\n  two\n'),
        contains("String get a => 'one two';"),
      );
    });
  });

  group('ICU works the same as in any other format', () {
    test('plural, select and formatting all reach the generator', () {
      final source = _generated('''
wallet:
  cards: '{count, plural, one{# card} other{# cards}}'
  total: 'Total: {amount, number, currency:USD}'
profile:
  greeting: '{gender, select, male{Mr} female{Ms} other{Mx}}'
''');
      expect(source, contains('String cards({required num count})'));
      expect(source, contains('_enNumberCurrencyUsd'));
      expect(source, contains('enum ProfileGreetingGender'));
    });

    test('ICU apostrophe quoting survives YAML quoting', () {
      // Both languages escape a quote by doubling it, which is a good way to
      // get this wrong.
      expect(
        _generated("a: 'It''''s a ''{''literal brace''}'''"),
        contains(r"String get a => 'It\'s a {literal brace}';"),
      );
    });
  });
}

/// The one YAML mistake everybody makes.
///
/// Nearly every ICU message starts with `{`, which YAML reads as the opening
/// of a flow mapping. `package:yaml` then says "Expected a key while parsing
/// a block mapping", which is accurate and mentions neither translations nor
/// quoting, and is the first thing a newcomer to the YAML format sees.
void _unquotedBraceHint() {
  group('an unquoted brace', () {
    test('the diagnostic says to quote the message', () {
      final result = runGenerator({'en.yaml': 'brace: {n} things\n'});

      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'invalid_yaml',
      );
      expect(diagnostic.details, isNotNull);
      expect(diagnostic.details, contains('must be quoted'));
      expect(diagnostic.details, contains('flow mapping'));
      // And shows the fix, because "quote it" is ambiguous about which quotes.
      expect(diagnostic.details, contains("'{name}, hello'"));
    });

    test('a quoted message parses', () {
      final result = runGenerator({'en.yaml': "brace: '{n} things'\n"});
      expect(errorsOf(result), isEmpty);
    });

    test('an unrelated YAML error keeps its own message and adds no hint', () {
      // The hint is attached by what the parser complained about, not to
      // every failure, so a genuine indentation mistake is not answered with
      // advice about braces.
      final result = runGenerator({'en.yaml': 'a: 1\n  b: 2\n'});

      final diagnostic = result.diagnostics.firstWhere(
        (d) => d.code == 'invalid_yaml',
      );
      expect(diagnostic.details, isNull);
    });
  });
}
