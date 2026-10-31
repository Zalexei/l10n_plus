/// Parser, validator and Dart code generator for `l10n_plus` translations.
///
/// The generator is a development time dependency: nothing here is meant to be
/// shipped inside an application.
library;

export 'src/config.dart' show FlutterConfig, L10nPlusConfig;
export 'src/diagnostic.dart' show Diagnostic, DiagnosticCollector, Severity;
export 'src/pipeline.dart'
    show
        GeneratedFile,
        GenerationResult,
        L10nPlusGenerator,
        LocaleCoverage,
        TranslationInput;
export 'src/source/source_parser.dart' show TranslationSourceParser;
export 'src/validation/unused_key_scanner.dart'
    show DartSource, TranslationKey, UnusedKeyReport, UnusedKeyScanner;
