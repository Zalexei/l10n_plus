import 'package:l10n_plus/l10n_plus.dart';
import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:test/test.dart';

({L10nPlusConfig? config, List<Diagnostic> diagnostics}) parse(String yaml) {
  final diagnostics = DiagnosticCollector();
  final config = L10nPlusConfig.parse(
    yaml,
    uri: Uri.parse('mem:l10n_plus.yaml'),
    diagnostics: diagnostics,
  );
  return (config: config, diagnostics: diagnostics.diagnostics);
}

void main() {
  test('applies defaults around the required base locale', () {
    final result = parse('base_locale: en');
    final config = result.config!;
    expect(config.inputDirectory, 'translations');
    expect(config.outputDirectory, 'lib/generated');
    expect(config.baseLocale, const L10nLocale('en'));
    expect(config.fallbackLocale, const L10nLocale('en'));
    expect(config.className, 'AppLocalizations');
    expect(config.flutter.enabled, isTrue);
    expect(config.flutter.contextExtension, 'l10n');
    expect(result.diagnostics, isEmpty);
  });

  test('derives output file names from the class name', () {
    final config = parse('base_locale: en\nclass_name: MyStrings').config!;
    expect(config.outputFileName, 'my_strings.g.dart');
    expect(config.flutterOutputFileName, 'my_strings_flutter.g.dart');
  });

  test('requires a base locale', () {
    final result = parse('output_directory: lib');
    expect(result.config, isNull);
    expect(result.diagnostics.single.code, 'invalid_config');
    expect(result.diagnostics.single.details, contains('base_locale: en'));
  });

  test('rejects an invalid locale', () {
    expect(parse('base_locale: "!!"').config, isNull);
  });

  test('warns about unknown keys', () {
    final result = parse('base_locale: en\ninput_dir: translations');
    expect(result.config, isNotNull);
    expect(result.diagnostics.single.code, 'unknown_config_key');
    expect(result.diagnostics.single.severity, Severity.warning);
  });

  test('warns about a class name that is not upper camel case', () {
    final result = parse('base_locale: en\nclass_name: app_strings');
    expect(
      result.diagnostics.map((d) => d.message),
      contains(contains('upper camel case')),
    );
  });

  test('reports malformed YAML with a span', () {
    final result = parse('base_locale: [en\n');
    expect(result.config, isNull);
    expect(result.diagnostics.single.span, isNotNull);
  });

  test('reads the flutter section', () {
    final config = parse(
      'base_locale: en\nflutter:\n  enabled: false\n'
      '  context_extension: strings',
    ).config!;
    expect(config.flutter.enabled, isFalse);
    expect(config.flutter.contextExtension, 'strings');
  });
}
