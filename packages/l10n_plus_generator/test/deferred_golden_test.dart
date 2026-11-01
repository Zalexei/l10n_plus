@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The `deferred` fixture, generated and compared against its goldens.
///
/// `deferred_locales` is the one option that changes the *shape* of the
/// output rather than the code inside it: the locales stop being `part`s of
/// one library and become libraries behind deferred imports, which is what
/// lets a web build put each one in a chunk of its own. So the assertions
/// here are about the layout — which import is deferred, which is not, and
/// what a chunk is allowed to reach.
///
/// The goldens are analyzed like every other one, executed by
/// `deferred_runtime_test.dart`, and driven through a real widget tree by
/// `packages/l10n_plus_flutter/test/deferred_locales_test.dart`.
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
  final root = p.join(_packageRoot, 'test/fixtures/deferred');
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
    final goldenDir = p.join(_packageRoot, 'test/goldens/deferred');

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

  test('the locales are libraries, not parts', () {
    // The whole difference. A `part` is compiled into its library and cannot
    // be a chunk; `deferred` needs something that can be loaded on its own.
    final shared = _file(_run(), 'app_localizations.g.dart');
    expect(shared, isNot(contains('part ')));
    expect(
      _file(_run(), 'app_localizations_ru.g.dart'),
      isNot(contains('part of')),
    );
  });

  test('every locale but the fallback is deferred', () {
    // Something has to be renderable before anything has loaded, so the
    // fallback locale is in the first download whatever else is not.
    final shared = _file(_run(), 'app_localizations.g.dart');
    expect(
      shared,
      contains("import 'app_localizations_en.g.dart' as _l10nEn;"),
    );
    expect(
      shared,
      contains("import 'app_localizations_ru.g.dart' deferred as _l10nRu;"),
    );
    expect(
      shared,
      contains("import 'app_localizations_de.g.dart' deferred as _l10nDe;"),
    );
  });

  test('a locale library reaches nothing but the shared one', () {
    // A chunk that named another locale's library would be a chunk that loads
    // it too, which is the thing being avoided. So each locale declares the
    // formatters it uses itself, privately, even the ones another locale
    // declares identically.
    final ru = _file(_run(), 'app_localizations_ru.g.dart');
    expect(ru, contains("import 'app_localizations.g.dart';"));
    expect(ru, isNot(contains('app_localizations_en.g.dart')));
    expect(ru, isNot(contains('app_localizations_de.g.dart')));
    expect(ru, contains('final NumberFormat _ruNumberCurrencyRub'));
    // Its own date format helper, because the shared file declares none.
    expect(ru, contains('DateFormat _dateFormat('));
    expect(
      _file(_run(), 'app_localizations.g.dart'),
      isNot(contains('DateFormat _dateFormat(')),
    );
  });

  test('the shared file holds no translations and no formatters', () {
    final shared = _file(_run(), 'app_localizations.g.dart');
    expect(shared, isNot(contains("import 'package:intl/intl.dart';")));
    expect(shared, isNot(contains('NumberFormat')));
    expect(shared, contains('abstract interface class AppLocalizations'));
  });

  test('the const instance is built where there is no prefix', () {
    // `const` of a class behind a deferred prefix is a compile error, so the
    // shared file cannot name the class at all. What crosses the boundary is
    // a getter returning an interface the shared file declared itself.
    expect(
      _file(_run(), 'app_localizations_ru.g.dart'),
      contains(
        'AppLocalizations get translations => const AppLocalizationsRu();',
      ),
    );
    final shared = _file(_run(), 'app_localizations.g.dart');
    expect(shared, isNot(contains('const AppLocalizationsRu(')));
    expect(shared, contains('_l10nRuLoaded ?? _l10nEn.translations'));
  });

  test('the enum says it loads on demand, and how', () {
    final shared = _file(_run(), 'app_localizations.g.dart');
    expect(
      shared,
      contains('enum AppLocale implements AppLocaleBase, DeferredAppLocale {'),
    );
    expect(shared, contains('await _l10nRu.loadLibrary();'));
    expect(shared, contains('static Future<void> loadAll()'));
    expect(shared, contains('bool get isLoaded'));
  });

  test('one nullable variable per locale rather than a map', () {
    // Every `context.l10n` goes through `translations`; a map read is a hash
    // on that path and a field read behind an enum switch is what the non
    // deferred layout already costs.
    final shared = _file(_run(), 'app_localizations.g.dart');
    expect(shared, contains('AppLocalizations? _l10nRuLoaded;'));
    expect(shared, isNot(contains('Map<AppLocale')));
  });
}
