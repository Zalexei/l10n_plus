@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The rich text fixture, generated and compared against its goldens.
///
/// Its own file rather than another entry in `codegen_golden_test.dart`,
/// because this fixture carries the assertions about rich text that the
/// format fixtures have no reason to: that the base file is data and the
/// Flutter wrapper is where `TextSpan` appears.
///
/// The goldens are analyzed like every other one, which type checks the
/// generated `L10nSpan` tree against the real runtime and the generated
/// wrapper against the real `l10n_plus_flutter`. They are also executed:
/// `rich_runtime_test.dart` runs the base file, and the widget test in
/// `packages/l10n_plus_flutter/test` runs the wrapper.
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
  final root = p.join(_packageRoot, 'test/fixtures/rich');
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
    final goldenDir = p.join(_packageRoot, 'test/goldens/rich');

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
      _run().files.map((f) => f.contents),
      _run().files.map((f) => f.contents),
    );
  });

  test('the base file is data: spans, and nothing from Flutter', () {
    final core = _file(_run(), 'app_localizations.g.dart');
    expect(core, contains('List<L10nSpan> get terms;'));
    expect(core, isNot(contains('package:flutter')));
    // `L10nTextSpan` is the data type and ends in the same word, so the
    // claim is about Flutter's `TextSpan` standing on its own.
    expect(core, isNot(matches(RegExp(r'\bTextSpan'))));
    expect(core, isNot(contains('InlineSpan')));
    // A message with no placeholder is a const list, so reading it allocates
    // nothing — the same claim the namespace accessors make.
    expect(core, contains('List<L10nSpan> get terms => const ['));
    // A message with one does not pretend to be.
    expect(core, contains('List<L10nSpan> greeting({required String name,'));
  });

  test('the wrapper lives in the glue, one per namespace with rich text', () {
    final glue = _file(_run(), 'app_localizations_flutter.g.dart');
    // The root has a rich message of its own, so it gets an extension too.
    expect(
      glue,
      contains(
        'extension AppLocalizationsRichText on '
        'AppLocalizations {',
      ),
    );
    expect(glue, contains(r'extension $LegalRichText on $Legal {'));
    expect(glue, contains('TextSpan bannerRich({'));
    expect(glue, contains('required L10nSpanBuilder link'));
    expect(glue, contains('required L10nSpanBuilder bold'));
    expect(glue, contains('required L10nSpanBuilder italic'));
    // The plain message in the same namespace gets no wrapper.
    expect(glue, isNot(contains('noticeRich')));
  });

  test('a literal "<" in a plain message is still literal', () {
    final core = _file(_run(), 'app_localizations.g.dart');
    expect(
      core,
      contains(
        "String get notice => 'Angle brackets such as <b> stay literal here';",
      ),
    );
  });
}
