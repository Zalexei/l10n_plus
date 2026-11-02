@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The `interfaces` fixture, generated and compared against its goldens.
///
/// Both forms of the configuration — a container and an explicit list — and
/// two locales, so the interface is asserted to be declared once for the
/// project rather than once per locale. What the generated types *do* is
/// executed by `interfaces_runtime_test.dart`; what is refused is asserted by
/// `interfaces_test.dart`.
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
  final root = p.join(_packageRoot, 'test/fixtures/interfaces');
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
    final goldenDir = p.join(_packageRoot, 'test/goldens/interfaces');

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

  test('one declaration per interface, for the whole project', () {
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(
      'abstract interface class ChangeData {'.allMatches(source).length,
      1,
    );
    expect('abstract interface class Plan {'.allMatches(source).length, 1);
  });

  test('the supertype is on the namespaces interface, not on its classes', () {
    // Where it has to be: the accessor that hands a namespace out is typed as
    // the interface, so a supertype only the locale classes implemented would
    // be invisible to every caller. One clause instead of one per locale, and
    // `interfaces_runtime_test.dart` is what found that out.
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(
      source,
      contains(r'abstract interface class $PlansFree implements Plan {'),
    );
    expect(source, contains(r'class $PlansFreeEn implements $PlansFree {'));
    expect(source, contains(r'class $PlansFreeRu implements $PlansFree {'));
    // And the shared type is the project's, not one per locale.
    expect(source, isNot(contains('PlanEn')));
    expect(source, isNot(contains('PlanRu')));
  });

  test('the member text is the namespaces own, character for character', () {
    // The interface and the namespace both emit `MessageModel.declaration`,
    // which is why a namespace satisfies its supertype by having been
    // generated at all. If the two ever drifted, this is where it shows.
    final source = _file(_run(), 'app_localizations.g.dart');
    for (final member in [
      'String get title;',
      'String footer({required String year});',
      'List<String> get rows;',
    ]) {
      // Once in `$OnboardingWhatsNewV2`, once in `$OnboardingWhatsNewV3`,
      // once in `ChangeData`.
      expect(member.allMatches(source).length, 3, reason: member);
    }
  });

  test(
    'a nested namespace is the shared type here and the narrow one there',
    () {
      // The two declarations that make covariance do the work: the supertype
      // promises `ChangeMeta`, the namespace's own interface promises its own
      // nested type, and Dart accepts the narrower override. So a caller
      // holding `ChangeData` reads `meta.date`, and a caller holding
      // `$OnboardingWhatsNewV2` keeps everything it had — a rich text
      // extension included, since those are declared on the narrow type.
      final source = _file(_run(), 'app_localizations.g.dart');
      expect(source, contains('  ChangeMeta get meta;'));
      expect(source, contains(r'  $OnboardingWhatsNewV2Meta get meta;'));
      expect(
        source,
        contains(
          r'  $OnboardingWhatsNewV2Meta get meta => '
          r'const $OnboardingWhatsNewV2MetaEn();',
        ),
      );
      expect(
        'abstract interface class ChangeMeta {'.allMatches(source).length,
        1,
      );
    },
  );

  test('a member that takes an argument is a method, not a getter', () {
    expect(
      _file(_run(), 'app_localizations.g.dart'),
      contains('  String footer({required String year});'),
    );
  });

  test('with overrides off the values stay const', () {
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains("String get title => 'New in 2.0';"));
    expect(source, contains("List<String> get rows => const ['Add sync'];"));
  });

  test('the doc of the shared type names where the members came from', () {
    expect(
      _file(_run(), 'app_localizations.g.dart'),
      contains('/// The members shared by `plans.free` and `plans.pro`.'),
    );
  });
}
