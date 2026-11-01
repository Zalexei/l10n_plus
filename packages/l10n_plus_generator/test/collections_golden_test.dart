@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The `collections` fixture, generated and compared against its goldens.
///
/// A list and a map, with `runtime_overrides` on — which is the half of the
/// feature that had a decision in it. There each element becomes a private
/// member that consults the store, so a bundle can replace one item; with
/// overrides off the elements are written into a `const` collection and
/// reading one allocates nothing. `collections_test.dart` asserts that half
/// on the same shapes.
///
/// Executed by `collections_runtime_test.dart`.
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
  final root = p.join(_packageRoot, 'test/fixtures/collections');
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
    final goldenDir = p.join(_packageRoot, 'test/goldens/collections');

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

  test('a list is one accessor, not a namespace of indices', () {
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains('List<String> get steps;'));
    // Which is the whole difference: before this, an array was an error and a
    // group of `0`, `1`, `2` keys would have generated a class with members
    // called `$0`.
    expect(source, isNot(contains(r'String get $0')));
    expect(source, isNot(contains(r'class $OnboardingSteps')));
  });

  test('a map is one accessor, and the suffix is not part of the API', () {
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains('Map<String, String> get countries;'));
    expect(source, isNot(contains('countriesMap')));
    expect(source, isNot(contains(r'(map)')));
  });

  test('the doc line says how many and, for a map, which', () {
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains('/// `en`: 3 messages, in order.'));
    expect(source, contains('/// `en`: 3 messages, keyed fr, de, jp.'));
  });

  test('with overrides on, each element consults the store', () {
    // The decision: inlined literals could not change when a bundle replaces
    // one item of a list, so each element becomes a member of its own and the
    // collection is built from them.
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains(r'String get _steps$0 {'));
    expect(
      source,
      contains("L10nOverrides.text(_\$locale, 'onboarding.steps.0')"),
    );
    expect(
      source,
      contains(r'List<String> get steps => [_steps$0, _steps$1, _steps$2];'),
    );
  });

  test('an override key does not carry the (map) suffix', () {
    // The suffix is a generation directive, not part of the message's
    // identity: a bundle names `countries.fr`.
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains("L10nOverrides.text(_\$locale, 'countries.fr')"));
    expect(source, isNot(contains('countries(map).fr')));
  });

  test('a record is one interface and one class per locale', () {
    // Not a class per element: the values are known while generating, so the
    // class carries them as fields and the list is one canonicalized
    // constant — or, with overrides on as here, one list of members.
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(
      source,
      contains('abstract interface class \$OnboardingPagesItem {'),
    );
    expect(source, contains('String get title;'));
    expect(
      source,
      contains(
        'const \$OnboardingPagesItemEn({'
        'required this.title, required this.body});',
      ),
    );
    // One class per locale, not per element.
    expect(
      RegExp(r'class \$OnboardingPagesItem[A-Z]').allMatches(source).length,
      2,
    );
    expect(source, contains('List<\$OnboardingPagesItem> get pages;'));
  });

  test('a map of records is keyed by the map and typed by the element', () {
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains('Map<String, \$PlansItem> get plans;'));
    expect(source, contains('abstract interface class \$PlansItem {'));
  });

  test('a record field is overridable on its own', () {
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains(r'String get _pages$0$title {'));
    expect(
      source,
      contains("L10nOverrides.text(_\$locale, 'onboarding.pages.1.body')"),
    );
    expect(source, contains(r'$OnboardingPagesItemEn(title: _pages$1$title'));
  });

  test('every element is in the overridable surface', () {
    // So `check-overrides` can refuse a bundle naming an element that does
    // not exist, which is what makes the keys a build-time fact here too.
    final result = _run();
    expect(result.overrides.localeTags, ['en', 'ru']);
    final schema = result.overrides.forLocale('en')!;
    expect(
      schema.messages.keys,
      containsAll(<String>[
        'onboarding.steps.0',
        'onboarding.steps.2',
        'countries.fr',
        'countries.jp',
      ]),
    );
  });
}
