@TestOn('vm')
library;

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:l10n_plus_generator/src/diagnostic.dart' show DiagnosticCodes;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `dynamic_keys`: what it refuses, and what that refusal is protecting.
///
/// The feature exists because server-driven copy is real. The shape it took —
/// a generated enum rather than a string lookup — is what keeps the set of
/// keys a build-time fact, and most of this file is the boundary of that:
/// every message a key could stand for has to be something a key *can* stand
/// for, which rules out two kinds and makes the ruling out an error rather
/// than a surprise.
///
/// What the generated code does is asserted by `dynamic_keys_golden_test.dart`
/// and executed by `dynamic_keys_runtime_test.dart`.
String _config(String keys) =>
    'input_directory: translations\n'
    'output_directory: lib/generated\n'
    'base_locale: en\n'
    'fallback_locale: en\n'
    'class_name: AppLocalizations\n'
    'locale_enum_name: AppLocale\n'
    'dynamic_keys: $keys\n'
    'flutter:\n'
    '  enabled: false\n';

const String _plain =
    'input_directory: translations\n'
    'output_directory: lib/generated\n'
    'base_locale: en\n'
    'fallback_locale: en\n'
    'class_name: AppLocalizations\n'
    'locale_enum_name: AppLocale\n'
    'flutter:\n'
    '  enabled: false\n';

GenerationResult _run(String messages, {String keys = '[errors]'}) =>
    runGenerator({'en.json': messages}, configYaml: _config(keys));

String _generated(String messages, {String keys = '[errors]'}) {
  final result = _run(messages, keys: keys);
  expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));
  return result.files.map((file) => file.contents).join('\n');
}

Diagnostic _only(String messages, {String keys = '[errors]'}) {
  final reports = _run(messages, keys: keys).diagnostics;
  expect(reports, hasLength(1), reason: reports.join('\n'));
  return reports.single;
}

void main() {
  group('what it generates', () {
    test('an enum of the namespace, and a lookup total over it', () {
      final source = _generated(
        '{"errors": {"offline": "Offline", "unknown": "Unknown"}}',
      );
      expect(source, contains('enum ErrorsKey {'));
      expect(source, contains("offline('offline'),"));
      expect(source, contains('String operator [](ErrorsKey key);'));
      expect(source, contains('ErrorsKey.offline => offline,'));
    });

    test('two namespaces are two enums, named after their paths', () {
      final source = _generated(
        '{"errors": {"a": "A"}, "shop": {"countries": {"fr": "France"}}}',
        keys: '[errors, shop.countries]',
      );
      expect(source, contains('enum ErrorsKey {'));
      expect(source, contains('enum ShopCountriesKey {'));
    });

    test('a project that names none generates what it always did', () {
      // The option is additive and opt-in, so the promise every other option
      // in this library makes holds here too.
      const messages = '{"errors": {"a": "A"}, "b": "B"}';
      expect(
        runGenerator({
          'en.json': messages,
        }, configYaml: _plain).files.map((file) => file.contents).join('\n'),
        runGenerator({
          'en.json': messages,
        }, configYaml: _config('[]')).files.map((f) => f.contents).join('\n'),
      );
    });

    test('a key reached only by the enum is not called unused', () {
      // The lookup names every message of the namespace, so the scan that
      // looks for names in Dart sources finds them. Asserted because the
      // alternative — advice to delete a key a server depends on — is the one
      // direction that scan must not err in.
      final result = _run('{"errors": {"offline": "Offline"}}');
      expect(errorsOf(result), isEmpty);
      final unused = UnusedKeyScanner.scan(
        keys: result.keys,
        sources: const [
          DartSource(
            path: 'lib/main.dart',
            content: 'void f() { t.errors[ErrorsKey.offline]; }',
          ),
        ],
      );
      expect(unused.isEmpty, isTrue, reason: unused.diagnostics.join('\n'));
    });
  });

  group('what it refuses', () {
    test('a message that takes arguments', () {
      // The heart of it. A string naming a message cannot carry the values
      // that message needs, and a map of them would be the run time lookup
      // this whole design avoids.
      final report = _only('{"errors": {"declined": "Card {last4} declined"}}');
      expect(report.code, 'unaddressable_dynamic_key');
      expect(report.message, contains('takes 1 argument'));
      expect(report.message, contains('last4'));
      expect(report.details, contains('cannot carry its values'));
    });

    test('and says how many, so the fix is visible', () {
      final report = _only('{"errors": {"a": "{x} and {y}"}}');
      expect(report.message, contains('takes 2 arguments'));
      expect(report.message, contains('x, y'));
    });

    test('a rich message, which renders spans rather than a string', () {
      final report = _only(
        '{"errors": {"terms(rich)": "See the <link>terms</link>"}}',
      );
      expect(report.code, 'unaddressable_dynamic_key');
      expect(report.message, contains('list of spans'));
    });

    test('a path that names a message rather than a namespace', () {
      final report = _only('{"errors": "Oops"}');
      expect(report.code, 'invalid_config');
      expect(report.message, contains('a message rather than a namespace'));
    });

    test('a path nothing defines, with the near miss offered', () {
      final report = _only('{"error": {"a": "A"}}');
      expect(report.code, 'invalid_config');
      expect(report.details, contains('Did you mean "error"?'));
      expect(report.details, contains('Namespaces:'));
    });

    test('a namespace with no message under it', () {
      // An enum cannot be empty, so there would be nothing to generate.
      final report = _only('{"errors": {"inner": {"deep": {}}}}');
      expect(report.code, 'invalid_config');
      expect(report.message, contains('no addressable message'));
    });

    test('two keys that would become one enum value', () {
      final report = _only(
        '{"errors": {"payment_declined": "A", "payment": {"declined": "B"}}}',
      );
      expect(report.code, 'identifier_collision');
      expect(report.message, contains('"payment_declined"'));
      expect(report.message, contains('"payment.declined"'));
      expect(report.message, contains('ErrorsKey'));
    });

    test('an enum name already taken by something generated', () {
      // Classes, enums and interfaces share one namespace in Dart, and a key
      // enum competes for it like everything else. Here the generated root
      // class got there first.
      final reports = runGenerator(
        {'en.json': '{"errors": {"a": "A"}}'},
        configYaml:
            'input_directory: translations\n'
            'output_directory: lib/generated\n'
            'base_locale: en\n'
            'fallback_locale: en\n'
            'class_name: ErrorsKey\n'
            'locale_enum_name: AppLocale\n'
            'dynamic_keys: [errors]\n'
            'flutter:\n'
            '  enabled: false\n',
      ).diagnostics;
      expect(reports.map((d) => d.code), contains('enum_name_collision'));
      expect(
        reports.firstWhere((d) => d.code == 'enum_name_collision').message,
        contains('ErrorsKey'),
      );
    });

    test('every code it reports is a registered diagnostic code', () {
      expect(
        DiagnosticCodes.alwaysErrors,
        contains('unaddressable_dynamic_key'),
      );
    });
  });

  group('the configuration itself', () {
    List<Diagnostic> report(String keys) => runGenerator({
      'en.json': '{"errors": {"a": "A"}}',
    }, configYaml: _config(keys)).diagnostics;

    test('an entry that is not a string is dropped with a warning', () {
      final diagnostics = report('[errors, 7]');
      expect(diagnostics.map((d) => d.code), ['invalid_config']);
      expect(diagnostics.single.severity, Severity.warning);
      // And the usable entry still took effect.
      expect(
        runGenerator({
          'en.json': '{"errors": {"a": "A"}}',
        }, configYaml: _config('[errors, 7]')).files.first.contents,
        contains('enum ErrorsKey'),
      );
    });

    test('a repeated entry is named once and used once', () {
      final diagnostics = report('[errors, errors]');
      expect(diagnostics.map((d) => d.code), ['invalid_config']);
      expect(diagnostics.single.message, contains('twice'));
    });

    test('not a list at all is a warning, not a crash', () {
      final diagnostics = report('errors');
      expect(diagnostics.map((d) => d.code), ['invalid_config']);
      expect(diagnostics.single.details, contains('dynamic_keys: ['));
    });
  });
}
