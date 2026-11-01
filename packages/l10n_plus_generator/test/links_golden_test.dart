@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The `links` fixture, generated and compared against its goldens.
///
/// Links with `runtime_overrides` on, which is the combination that had a
/// decision in it: there a link compiles to a call on a `const` receiver, so
/// overriding the target reaches every message that links to it. With
/// overrides off the same links are written in place and cost nothing, which
/// `link_test.dart` asserts on the same shapes.
///
/// The goldens are analyzed like every other one, and executed by
/// `links_runtime_test.dart` — reading the source proves the call was
/// written, running it proves the text that comes out is the target's.
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
  final root = p.join(_packageRoot, 'test/fixtures/links');
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
    final goldenDir = p.join(_packageRoot, 'test/goldens/links');

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

  test('a link is a call on a const receiver, not a field hop', () {
    // No pointer to a root object anywhere: every generated class is `const`
    // constructible with no fields, so naming one from another costs nothing
    // and Dart canonicalizes the instance. This is the only place generated
    // code reads a message other than its own.
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains(r"'Welcome to ${const $BrandEn().name}'"));
    expect(source, contains(r"'Добро пожаловать в ${const $BrandRu().name}'"));
    expect(source, isNot(contains('_root')));
  });

  test('a linked target hands over its parameters', () {
    final source = _file(_run(), 'app_localizations.g.dart');
    // `invitation` writes no placeholder of its own and takes `name`, because
    // the message it links to does.
    expect(source, contains('String invitation({required String name});'));
    // `cart` links to a plural, so it takes the count the plural selects on.
    expect(source, contains('String cart({required num n});'));
    expect(source, contains(r'const AppLocalizationsEn().items(n: n)'));
  });

  test('the doc comment shows the link, the body shows the target', () {
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(source, contains('/// `en`: Welcome to @:brand.name'));
    expect(source, contains(r'${const $BrandEn().name}'));
  });

  test('a link inside a plural branch is resolved per branch', () {
    // Russian has four branches here and each links to the brand; nothing
    // about a link cares which branch it stands in.
    final source = _file(_run(), 'app_localizations.g.dart');
    expect(
      RegExp(r'const \$BrandRu\(\)\.short').allMatches(source).length,
      greaterThanOrEqualTo(4),
    );
  });

  test('a quoted at sign is text', () {
    // `'@':` in the translation, quoted by the apostrophe that already quotes
    // `{`, `}` and `#` — so a message that wants the two characters can say
    // so without a second escape mechanism.
    expect(_file(_run(), 'app_localizations.g.dart'), contains('@:  '));
  });
}
