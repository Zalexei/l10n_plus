import 'dart:io';
import 'dart:isolate';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Root of the generator package, however the suite was started.
///
/// Not `Directory.current`: the tests are run from the workspace root too.
final String packageRoot = p.dirname(
  p.dirname(
    Isolate.resolvePackageUriSync(
      Uri.parse('package:l10n_plus_generator/l10n_plus_generator.dart'),
    )!.toFilePath(),
  ),
);

/// A project on disk, copied so that a test may write to it.
final class Project {
  /// Creates a handle to a project rooted at [root].
  Project(this.root);

  /// Absolute path of the project root.
  final String root;

  /// The configuration, parsed.
  L10nPlusConfig get config {
    final file = File(p.join(root, 'l10n_plus.yaml'));
    final parsed = L10nPlusConfig.parse(
      file.readAsStringSync(),
      uri: file.uri,
      diagnostics: DiagnosticCollector(),
    );
    return parsed!;
  }

  /// Every translation file, by path relative to the project root.
  Map<String, String> get translations {
    final input = Directory(p.join(root, config.inputDirectory));
    return {
      for (final entity in input.listSync(recursive: true))
        if (entity is File)
          p.relative(entity.path, from: root): entity.readAsStringSync(),
    };
  }

  /// Reads the catalog, failing the test if anything is wrong with the files.
  TranslationCatalog get catalog {
    final diagnostics = DiagnosticCollector();
    final catalog = TranslationCatalog.load(
      config: config,
      projectRoot: root,
      diagnostics: diagnostics,
    );
    expect(
      diagnostics.diagnostics.where((d) => d.severity == Severity.error),
      isEmpty,
      reason: 'the fixture should read cleanly',
    );
    return catalog!;
  }

  /// Writes a translation file, by path relative to the project root.
  void write(String relative, String contents) =>
      File(p.join(root, relative)).writeAsStringSync(contents);
}

/// Copies the fixture called [name] into a temporary directory.
///
/// A copy rather than the fixture itself, because `import` writes: a test that
/// edited `test/fixtures/` would leave the repository dirty and the next test
/// reading a different project than the one it was written against.
Project copyFixture(String name) {
  final source = Directory(p.join(packageRoot, 'test', 'fixtures', name));
  final root = Directory.systemTemp.createTempSync('l10n_plus_interchange');
  addTearDown(() => root.deleteSync(recursive: true));

  for (final entity in source.listSync(recursive: true)) {
    final relative = p.relative(entity.path, from: source.path);
    final target = p.join(root.path, relative);
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
      continue;
    }
    if (entity is File) {
      Directory(p.dirname(target)).createSync(recursive: true);
      entity.copySync(target);
    }
  }
  return Project(root.path);
}

/// Builds a project from [translations] and [configYaml] in a temporary
/// directory, for the cases no fixture covers.
Project makeProject({
  required Map<String, String> translations,
  required String configYaml,
}) {
  final root = Directory.systemTemp.createTempSync('l10n_plus_interchange');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'l10n_plus.yaml')).writeAsStringSync(configYaml);
  translations.forEach((name, contents) {
    final file = File(p.join(root.path, 'translations', name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  return Project(root.path);
}

/// The configuration most of these tests use: one file per locale, no Flutter.
const String interchangeConfigYaml = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
flutter:
  enabled: false
''';

/// Runs the CLI as a process, which is the only way to test an exit code.
ProcessResult runCli(String root, List<String> arguments) =>
    Process.runSync(Platform.resolvedExecutable, [
      'run',
      p.join(packageRoot, 'bin/l10n_plus_generator.dart'),
      ...arguments,
      '--no-highlight',
    ], workingDirectory: root);
