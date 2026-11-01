@TestOn('vm')
library;

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:l10n_plus_generator/src/diagnostic.dart' show DiagnosticCodes;
import 'package:test/test.dart';

import 'support/fixture.dart';

/// `interfaces`: a supertype several namespaces share, and what it refuses.
///
/// The feature is one line of configuration and one generated type, and
/// almost all of this file is the refusals — because the refusals are the
/// feature. Every package that infers a supertype from several subtrees
/// widens what they disagree about into a nullable member, which turns a
/// translation mistake into a `null` on the screen that read it. Here the
/// disagreement is the diagnostic.
String _config(String interfaces, {String dynamicKeys = ''}) =>
    'input_directory: translations\n'
    'output_directory: lib/generated\n'
    'base_locale: en\n'
    'fallback_locale: en\n'
    'class_name: AppLocalizations\n'
    'locale_enum_name: AppLocale\n'
    '${dynamicKeys.isEmpty ? '' : 'dynamic_keys: $dynamicKeys\n'}'
    'interfaces:\n'
    '$interfaces'
    'flutter:\n'
    '  enabled: false\n';

/// Two namespaces of the same shape, which is the case the feature is for.
const String _changes =
    '{"onboarding": {"whatsNew": {'
    '"v2": {"title": "New in 2.0", "rows": ["Add sync"]},'
    '"v3": {"title": "New in 3.0", "rows": ["Modes", "And more"]}'
    '}}}';

GenerationResult _run(
  String messages, {
  String interfaces = '  ChangeData: onboarding.whatsNew.*\n',
  String dynamicKeys = '',
}) => runGenerator({
  'en.json': messages,
}, configYaml: _config(interfaces, dynamicKeys: dynamicKeys));

String _generated(
  String messages, {
  String interfaces = '  ChangeData: onboarding.whatsNew.*\n',
}) {
  final result = _run(messages, interfaces: interfaces);
  expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));
  return result.files.map((file) => file.contents).join('\n');
}

Diagnostic _only(
  String messages, {
  String interfaces = '  ChangeData: onboarding.whatsNew.*\n',
  String dynamicKeys = '',
}) {
  final reports = _run(
    messages,
    interfaces: interfaces,
    dynamicKeys: dynamicKeys,
  ).diagnostics;
  expect(reports, hasLength(1), reason: reports.join('\n'));
  return reports.single;
}

void main() {
  group('what it generates', () {
    test('one interface, implemented by every namespace named', () {
      final source = _generated(_changes);

      expect(source, contains('abstract interface class ChangeData {'));
      expect(source, contains('  String get title;'));
      expect(source, contains('  List<String> get rows;'));
      expect(
        source,
        contains(
          'abstract interface class \$OnboardingWhatsNewV2 '
          'implements ChangeData {',
        ),
      );
      expect(
        source,
        contains(
          'abstract interface class \$OnboardingWhatsNewV3 '
          'implements ChangeData {',
        ),
      );
    });

    test('the doc names the namespaces it was read from', () {
      expect(
        _generated(_changes),
        contains(
          '/// The members shared by `onboarding.whatsNew.v2` and '
          '`onboarding.whatsNew.v3`.',
        ),
      );
    });

    test('nothing is generated for a project that asks for none', () {
      final plain = runGenerator({
        'en.json': _changes,
      }, configYaml: _config('')).files.map((f) => f.contents).join();
      expect(plain, isNot(contains('ChangeData')));
    });

    test('a single namespace is allowed, without the ".*"', () {
      final source = _generated(
        _changes,
        interfaces: '  Change: onboarding.whatsNew.v2\n',
      );
      expect(source, contains('abstract interface class Change {'));
      expect(
        source,
        contains('/// The members shared by `onboarding.whatsNew.v2`.'),
      );
    });

    test('two unrelated paths share one type', () {
      final source = _generated(
        '{"a": {"title": "A"}, "b": {"title": "B"}}',
        interfaces: '  Titled:\n    - a\n    - b\n',
      );
      expect(
        source,
        contains('abstract interface class \$A implements Titled {'),
      );
      expect(
        source,
        contains('abstract interface class \$B implements Titled {'),
      );
    });

    test('a namespace can implement two of them', () {
      final source = _generated(
        '{"a": {"title": "A"}, "b": {"title": "B"}}',
        interfaces: '  Titled:\n    - a\n    - b\n  Head: a\n',
      );
      expect(
        source,
        contains('abstract interface class \$A implements Head, Titled {'),
      );
    });

    test('a message that takes arguments is a method on the interface', () {
      final source = _generated(
        '{"a": {"hi": "Hi {name}"}, "b": {"hi": "Hallo {name}"}}',
        interfaces: '  Greeting:\n    - a\n    - b\n',
      );
      expect(source, contains('  String hi({required String name});'));
    });
  });

  group('it composes with the rest', () {
    /// The same configuration with [extra] lines added.
    String withOption(String extra) =>
        _config('  ChangeData: onboarding.whatsNew.*\n') + extra;

    test('with overrides on, the members stay public and the type stays', () {
      final result = runGenerator({
        'en.json': _changes,
      }, configYaml: withOption('runtime_overrides: true\n'));

      expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));
      final source = result.files.map((file) => file.contents).join('\n');
      expect(source, contains('abstract interface class ChangeData {'));
      expect(
        source,
        contains(
          'abstract interface class \$OnboardingWhatsNewV2 '
          'implements ChangeData {',
        ),
      );
      // The store is consulted behind the same public member, which is what
      // makes the supertype indifferent to the option: the body changed and
      // the declaration the interface names did not.
      expect(source, contains('String get title {'));
      expect(source, contains(r'$override'));
    });

    test('with one file per locale, the type is declared once', () {
      final result = runGenerator({
        'en.json': _changes,
        'ru.json':
            '{"onboarding": {"whatsNew": {'
            '"v2": {"title": "2.0", "rows": ["x"]},'
            '"v3": {"title": "3.0", "rows": ["y", "z"]}'
            '}}}',
      }, configYaml: withOption('file_per_locale: true\n'));

      expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));
      final declarations = result.files
          .where(
            (file) =>
                file.contents.contains('abstract interface class ChangeData'),
          )
          .length;
      expect(declarations, 1);
      // And it is the namespaces' own interfaces that implement it, in the
      // shared file: one clause for the project, not one per locale.
      expect(
        result.files
            .where((file) => file.contents.contains('implements ChangeData {'))
            .length,
        1,
      );
    });

    test('with Flutter on, the glue is unaffected', () {
      final result = runGenerator(
        {'en.json': _changes},
        configYaml: _config(
          '  ChangeData: onboarding.whatsNew.*\n',
        ).replaceFirst('  enabled: false', '  enabled: true'),
      );
      expect(errorsOf(result), isEmpty, reason: result.diagnostics.join('\n'));
    });
  });

  group('the members have to match', () {
    test('a missing member names both namespaces and the member', () {
      final diagnostic = _only(
        '{"onboarding": {"whatsNew": {'
        '"v2": {"title": "New in 2.0", "rows": ["Add sync"]},'
        '"v3": {"title": "New in 3.0"}'
        '}}}',
      );

      expect(diagnostic.code, 'invalid_interface');
      expect(
        diagnostic.message,
        '"onboarding.whatsNew.v3" does not have the members of '
        '"onboarding.whatsNew.v2", which "ChangeData" was read from.',
      );
      expect(diagnostic.details, contains('"rows" is missing'));
      // The reason the refusal exists rather than a nullable member.
      expect(diagnostic.details, contains('nullable member'));
    });

    test('an extra member is reported too', () {
      final diagnostic = _only(
        '{"a": {"title": "A"}, "b": {"title": "B", "body": "b"}}',
        interfaces: '  Titled:\n    - a\n    - b\n',
      );
      expect(diagnostic.details, contains('"body" is not in "a"'));
    });

    test('the same name with a different signature is a mismatch', () {
      final diagnostic = _only(
        '{"a": {"hi": "Hi {name}"}, "b": {"hi": "Hallo {firstName}"}}',
        interfaces: '  Greeting:\n    - a\n    - b\n',
      );
      expect(diagnostic.code, 'invalid_interface');
      expect(
        diagnostic.details,
        contains(
          '"hi" is `String hi({required String firstName})`, '
          'not `String hi({required String name})`',
        ),
      );
    });

    test('a list where the other has a map is a mismatch', () {
      final diagnostic = _only(
        '{"a": {"x": ["one"]}, "b": {"x(map)": {"k": "one"}}}',
        interfaces: '  Both:\n    - a\n    - b\n',
      );
      expect(
        diagnostic.details,
        contains(
          '"x" is `Map<String, String> get x`, not `List<String> get x`',
        ),
      );
    });

    test('a rich message against a plain one is a mismatch', () {
      final diagnostic = _only(
        '{"a": {"t(rich)": "<b>Hi</b>"}, "b": {"t": "Hi"}}',
        interfaces: '  Both:\n    - a\n    - b\n',
      );
      expect(
        diagnostic.details,
        contains('"t" is `String get t`, not `List<L10nSpan> get t`'),
      );
    });

    test('order within a namespace does not matter', () {
      final source = _generated(
        '{"a": {"title": "A", "body": "a"}, "b": {"body": "b", "title": "B"}}',
        interfaces: '  Titled:\n    - a\n    - b\n',
      );
      // The interface takes the first namespace's order, and the second
      // namespace is not asked to rewrite its file to match.
      expect(
        source,
        contains('abstract interface class \$B implements Titled {'),
      );
    });
  });

  group('what cannot be in one', () {
    test('a namespace that holds a namespace', () {
      final diagnostic = _only(
        '{"a": {"x": {"deep": "d"}}, "b": {"x": {"deep": "d"}}}',
        interfaces: '  Both:\n    - a\n    - b\n',
      );
      expect(diagnostic.code, 'invalid_interface');
      expect(
        diagnostic.message,
        '"a" cannot implement "Both", because it holds the namespace "a.x".',
      );
      expect(diagnostic.details, contains('named after its own path'));
    });

    test('a namespace whose list holds records', () {
      final diagnostic = _only(
        '{"a": {"x": [{"t": "t"}]}, "b": {"x": [{"t": "t"}]}}',
        interfaces: '  Both:\n    - a\n    - b\n',
      );
      expect(diagnostic.code, 'invalid_interface');
      expect(diagnostic.message, contains('the elements of "x" are records'));
    });

    test('a namespace addressed by key', () {
      final diagnostic = _only(
        '{"a": {"title": "A"}, "b": {"title": "B"}}',
        interfaces: '  Titled:\n    - a\n    - b\n',
        dynamicKeys: '[a]',
      );
      expect(diagnostic.code, 'invalid_interface');
      expect(diagnostic.message, contains('addressed by key through "AKey"'));
      expect(diagnostic.details, contains('and one is enough'));
    });

    test('and each of those is exactly one diagnostic', () {
      // The refusal stops the comparison: a namespace that was refused has no
      // member list, and "it is missing every member" is a second report of
      // the first one's cause.
      final codes = errorsOf(
        _run(
          '{"a": {"x": {"deep": "d"}}, "b": {"title": "B"}}',
          interfaces: '  Both:\n    - a\n    - b\n',
        ),
      );
      expect(codes, ['invalid_interface']);
    });
  });

  group('the configuration itself', () {
    test('a path that is not a namespace offers the nearest one', () {
      final diagnostic = _only(
        _changes,
        interfaces: '  ChangeData: onboarding.whatsnew.*\n',
      );
      expect(diagnostic.code, 'invalid_config');
      expect(diagnostic.message, contains('is not a namespace'));
      expect(
        diagnostic.details,
        contains('Did you mean "onboarding.whatsNew"'),
      );
    });

    test('a ".*" over a namespace of messages says to drop it', () {
      final diagnostic = _only(
        '{"a": {"title": "A"}}',
        interfaces: '  Titled: a.*\n',
      );
      expect(diagnostic.code, 'invalid_config');
      expect(diagnostic.details, contains('Drop the ".*"'));
    });

    test('a name that cannot be a Dart type is refused', () {
      final result = _run(_changes, interfaces: '  changeData: onboarding\n');
      final warning = result.diagnostics.singleWhere(
        (d) => d.code == 'invalid_config',
      );
      expect(warning.message, contains('cannot be a Dart type'));
      expect(warning.severity, Severity.warning);
    });

    test('a value that is neither a path nor a list of them', () {
      final result = _run(_changes, interfaces: '  ChangeData: 7\n');
      expect(
        result.diagnostics
            .singleWhere((d) => d.code == 'invalid_config')
            .message,
        contains('must be a namespace path or a list of them'),
      );
    });

    test('"interfaces" that is not a map', () {
      final result = runGenerator(
        {'en.json': _changes},
        configYaml: _config(
          '',
        ).replaceFirst('interfaces:\n', 'interfaces: 7\n'),
      );
      expect(
        result.diagnostics
            .singleWhere((d) => d.code == 'invalid_config')
            .details,
        contains('ChangeData: onboarding.whatsNew.*'),
      );
    });

    test('the same path twice in one interface is reported once', () {
      final result = _run(
        _changes,
        interfaces:
            '  ChangeData:\n'
            '    - onboarding.whatsNew.v2\n'
            '    - onboarding.whatsNew.v2\n',
      );
      expect(
        result.diagnostics
            .singleWhere((d) => d.code == 'invalid_config')
            .message,
        contains('names "onboarding.whatsNew.v2" twice'),
      );
      // And the interface is still generated from the one that was named.
      expect(errorsOf(result), isEmpty);
    });

    test('a name colliding with a generated type is reported', () {
      final diagnostic = _only(
        _changes,
        interfaces: '  AppLocalizations: onboarding.whatsNew.v2\n',
      );
      expect(diagnostic.code, 'type_name_collision');
    });

    test('"invalid_interface" is an error nobody can ignore', () {
      expect(DiagnosticCodes.alwaysErrors, contains('invalid_interface'));
      expect(
        DiagnosticCodes.suppressible,
        isNot(contains('invalid_interface')),
      );
    });
  });
}
