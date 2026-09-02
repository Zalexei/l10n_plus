import 'dart:io';

import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Default configuration used by [runGenerator] when none is given.
const String defaultConfigYaml = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
flutter:
  enabled: false
''';

/// Runs the whole pipeline over an on-disk fixture built from [translations].
///
/// Keys of [translations] are paths relative to the translation directory,
/// such as `en.json` or `en/wallet.json`. The temporary directory is deleted
/// when the test finishes.
GenerationResult runGenerator(
  Map<String, String> translations, {
  String configYaml = defaultConfigYaml,
  List<TranslationSourceParser>? parsers,
  String? pubspec,
}) {
  final root = Directory.systemTemp.createTempSync('l10n_plus_test');
  addTearDown(() => root.deleteSync(recursive: true));

  final input = Directory(p.join(root.path, 'translations'))
    ..createSync(recursive: true);
  translations.forEach((name, content) {
    // Names may carry directories, for patterns such as `{locale}/*`.
    final file = File(p.join(input.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });

  final configFile = File(p.join(root.path, 'l10n_plus.yaml'))
    ..writeAsStringSync(configYaml);
  if (pubspec != null) {
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
  }

  final diagnostics = DiagnosticCollector();
  final config = L10nPlusConfig.parse(
    configFile.readAsStringSync(),
    uri: configFile.uri,
    diagnostics: diagnostics,
  );
  if (config == null) {
    return GenerationResult(
      diagnostics: diagnostics.diagnostics,
      files: const [],
    );
  }

  final result = L10nPlusGenerator(
    config: config,
    projectRoot: root.path,
    parsers: parsers ?? L10nPlusGenerator.defaultParsers,
  ).run();
  return GenerationResult(
    diagnostics: [...diagnostics.diagnostics, ...result.diagnostics],
    files: result.files,
  );
}

/// Diagnostic codes of [result], in report order.
List<String> codesOf(GenerationResult result) =>
    result.diagnostics.map((d) => d.code).toList(growable: false);

/// Error codes of [result].
List<String> errorsOf(GenerationResult result) => result.diagnostics
    .where((d) => d.severity == Severity.error)
    .map((d) => d.code)
    .toList(growable: false);
