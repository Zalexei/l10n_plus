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

  group('a near miss is named', () {
    List<Diagnostic> parse(String yaml) {
      final diagnostics = DiagnosticCollector();
      L10nPlusConfig.parse(
        yaml,
        uri: Uri.parse('file:///l10n_plus.yaml'),
        diagnostics: diagnostics,
      );
      return diagnostics.diagnostics;
    }

    const base = 'base_locale: en\nfallback_locale: en\n';

    String? suggestion(String key) {
      final diagnostic = parse(
        '$base$key: true\n',
      ).firstWhere((d) => d.code == 'unknown_config_key');
      final match = RegExp(
        r'Did you mean "([a-z_]+)"',
      ).firstMatch(diagnostic.details ?? '');
      return match?.group(1);
    }

    test('one edit away', () {
      expect(suggestion('file_per_local'), 'file_per_locale');
      expect(suggestion('base_local'), 'base_locale');
      expect(suggestion('class_names'), 'class_name');
    });

    test('a transposition and a wrong separator', () {
      expect(suggestion('output-directory'), 'output_directory');
      expect(suggestion('fillMissingFromBase'), null);
    });

    test('a key that resembles nothing gets no guess', () {
      // A wrong suggestion is worse than the list of every key, which is
      // printed either way.
      expect(suggestion('translations'), null);
      expect(suggestion('locale'), null);
    });

    test('the list of known keys is printed regardless', () {
      final diagnostic = parse(
        '${base}file_per_local: true\n',
      ).firstWhere((d) => d.code == 'unknown_config_key');
      expect(diagnostic.details, contains('Known keys:'));
      expect(diagnostic.details, contains('file_per_locale'));
    });
  });
}
