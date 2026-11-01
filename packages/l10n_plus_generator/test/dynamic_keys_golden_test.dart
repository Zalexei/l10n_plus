@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The `dynamic_keys` fixture, generated and compared against its goldens.
///
/// `dynamic_keys` is the feature this library had no business having, and the
/// shape it took is the whole argument: not a string keyed lookup but a
/// generated enum, with the one nullable step at the boundary where a string
/// from outside arrives. These assertions are about that shape — what the
/// enum holds, what the lookup is total over, and what it delegates to.
///
/// Overrides are on in the fixture, so the goldens also pin the composition:
/// the lookup calls the members, so an overridden message is overridden
/// through the lookup too. `dynamic_keys_runtime_test.dart` executes that.
///
/// Set `UPDATE_GOLDENS=1` to rewrite the expected files.
bool get _updateGoldens => Platform.environment['UPDATE_GOLDENS'] == '1';

final String _packageRoot = p.dirname(
  p.dirname(
    Isolate.resolvePackageUriSync(
      Uri.parse('package:l10n_plus_generator/l10n_plus_generator.dart'),
    )!.toFilePath(),
  ),
);

GenerationResult _run() {
  final root = p.join(_packageRoot, 'test/fixtures/dynamic_keys');
  final configFile = File(p.join(root, 'l10n_plus.yaml'));
  final diagnostics = DiagnosticCollector();
  final config = L10nPlusConfig.parse(
    configFile.readAsStringSync(),
    uri: configFile.uri,
    diagnostics: diagnostics,
  )!;
  final result = L10nPlusGenerator(config: config, projectRoot: root).run();
  expect(
    result.diagnostics.where((d) => d.severity == Severity.error),
    isEmpty,
    reason: result.diagnostics.map((d) => d.format()).join('\n'),
  );
  return result;
}

String _file(GenerationResult result, String name) =>
    result.files.firstWhere((file) => p.basename(file.path) == name).contents;

void main() {
  test('matches its goldens', () {
    final result = _run();
    final goldenDir = p.join(_packageRoot, 'test/goldens/dynamic_keys');

    for (final file in result.files) {
      final golden = File(p.join(goldenDir, p.basename(file.path)));
      if (_updateGoldens) {
        golden.parent.createSync(recursive: true);
        golden.writeAsStringSync(file.contents);
        continue;
      }
      expect(
        golden.existsSync(),
        isTrue,
        reason: 'Missing golden ${golden.path}. Run UPDATE_GOLDENS=1.',
      );
      expect(
        file.contents,
        golden.readAsStringSync(),
        reason:
            'Generated ${p.basename(file.path)} drifted from its golden. '
            'Run UPDATE_GOLDENS=1 after reviewing the change.',
      );
    }
  });

  test('is deterministic across runs', () {
    expect(
      _run().files.map((file) => file.contents),
      _run().files.map((file) => file.contents),
    );
  });

  test('the enum carries the translation key, not the Dart name', () {
    // What a server sends is what the translation file calls the message.
    // `rate_limited` is one string; `rateLimited` is the identifier it
    // generated, and confusing the two would make the contract a function of
    // this generator's naming rules.
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains("rateLimited('rate_limited'),"));
    expect(source, contains("paymentDeclined('payment.declined'),"));
  });

  test('a nested key is dotted, and relative to the namespace', () {
    // Relative because the namespace is the contract: renaming the group it
    // sits under should not renegotiate every error code.
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains("/// `errors.payment.expired`."));
    // The last value ends the enum, so the separator is a semicolon.
    expect(source, contains("paymentExpired('payment.expired');"));
    expect(source, isNot(contains("('errors.payment.expired')")));
  });

  test('tryParse is the one step that can fail', () {
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains('static ErrorsKey? tryParse(String key)'));
    // And the lookup it feeds cannot: no nullable return, no `dynamic`.
    expect(source, contains('String operator [](ErrorsKey key)'));
    expect(source, isNot(contains('String? operator []')));
    expect(source, isNot(contains('dynamic operator []')));
  });

  test('the lookup delegates to the members rather than repeating them', () {
    // Which is what makes it compose: an overridden message is overridden
    // here, a linked one resolves the same way, and the lookup cannot drift
    // from the member because it is the member.
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains('ErrorsKey.unknown => unknown,'));
    expect(source, contains('ErrorsKey.paymentDeclined => payment.declined,'));
    // No second copy of the text anywhere in the lookup.
    expect(RegExp("'Your card was declined'").allMatches(source).length, 1);
  });

  test('a namespace nobody named gets no lookup', () {
    // Per namespace, not per project: `auth` is read by name, and nothing
    // about it changed.
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, isNot(contains('AuthKey')));
    expect(source, contains('String get title;'));
  });

  test('still no string keyed map anywhere', () {
    // The standing claim of the library, and the one this feature could most
    // easily have broken: what it generates is a switch over an enum, which
    // the compiler checks for exhaustiveness.
    final source = _file(_run(), 'app_localizations.g.dart');
    final parameter = 'void installOverrides(Map<String, Object> messages)';
    expect(source, contains(parameter));
    expect(source.replaceFirst(parameter, ''), isNot(contains('Map<String')));
  });
}
