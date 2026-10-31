/// Parser, validator and Dart code generator for `l10n_plus` translations.
///
/// The generator is a development time dependency: nothing here is meant to be
/// shipped inside an application.
library;

export 'src/config.dart' show FlutterConfig, L10nPlusConfig;
export 'src/diagnostic.dart' show Diagnostic, DiagnosticCollector, Severity;
export 'src/interchange/bundle.dart'
    show InterchangeBundle, InterchangeEntry, InterchangeFormat;
export 'src/interchange/catalog.dart'
    show
        CatalogEntry,
        CatalogFile,
        CatalogMessage,
        LocaleCatalog,
        TranslationCatalog,
        TranslationFileFormat;
export 'src/interchange/csv.dart' show Csv, CsvException, CsvField;
export 'src/interchange/editor.dart'
    show InsertionPoint, TextEdit, TranslationEditor;
export 'src/interchange/exporter.dart'
    show ExportCoverage, ExportFile, ExportResult, TranslationExporter;
export 'src/interchange/importer.dart'
    show
        ImportChange,
        ImportResult,
        ImportedLocale,
        ImportedMessage,
        PendingWrite,
        TranslationImporter;
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
