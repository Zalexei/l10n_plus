import 'package:l10n_plus/l10n_plus.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'diagnostic.dart';
import 'source/file_pattern.dart';
import 'model/dart_identifiers.dart';

/// Flutter specific generation options.
final class FlutterConfig {
  /// Creates Flutter options.
  const FlutterConfig({this.enabled = true, this.contextExtension = 'l10n'});

  /// Whether to emit the Flutter glue file.
  final bool enabled;

  /// Name of the `BuildContext` getter, e.g. `l10n` for `context.l10n`.
  final String contextExtension;
}

/// Everything `generate` and `analyze` need to know.
final class L10nPlusConfig {
  /// Creates a configuration.
  L10nPlusConfig({
    this.inputDirectory = 'translations',
    this.outputDirectory = 'lib/generated',
    required this.baseLocale,
    required this.fallbackLocale,
    this.className = 'AppLocalizations',
    this.localeEnumName = 'AppLocale',
    this.formatPluralNumbers = false,
    this.filePattern,
    this.filePerLocale = false,
    this.fillMissingFromBase = false,
    this.flutter = const FlutterConfig(),
  });

  /// Default configuration file name, relative to the project root.
  static const String defaultFileName = 'l10n_plus.yaml';

  /// Directory holding the translation files.
  final String inputDirectory;

  /// Directory the generated files are written to.
  final String outputDirectory;

  /// Locale that defines the generated API.
  final L10nLocale baseLocale;

  /// Locale used at run time when nothing matches.
  final L10nLocale fallbackLocale;

  /// Name of the generated root class.
  final String className;

  /// Name of the generated locale enum.
  final String localeEnumName;

  /// Whether `#` inside a plural is rendered through the locale's
  /// `NumberFormat` instead of interpolating the raw number.
  ///
  /// Off by default: honouring ICU here pulls `package:intl` into every
  /// project that writes a plural, which is most of them. Turning it on is a
  /// per project choice, and changes the output of existing messages.
  final bool formatPluralNumbers;

  /// Where the locale sits in a translation file's path, when the project
  /// said. `null` means it did not.
  ///
  /// Also decides how many files a locale may have: `{locale}` gives one file
  /// per locale, `*/{locale}` lets a locale be spread over a directory. Files
  /// of one locale are merged; a file name never reaches the generated API.
  ///
  /// The distinction from [pathPattern] matters for diagnostics: a configured
  /// pattern is a claim about the layout, so a file disagreeing with it is
  /// worth reporting. The default is a fallback and claims nothing — under it
  /// `app_en.arb` "matches" as the locale `app_EN`, and `@@locale` quietly
  /// corrects it, which is what makes a `gen_l10n` bundle work unedited.
  final FilePattern? filePattern;

  /// The pattern to match paths with, configured or default.
  FilePattern get pathPattern => filePattern ?? FilePattern.fallback;

  /// Whether a key missing from a locale falls back to the base locale.
  ///
  /// Off by default: an incomplete locale is normally a mistake. On, it is a
  /// warning instead of an error and the message renders exactly as the base
  /// locale renders it — same text, same plural rules, same formatting —
  /// because a half translated message would be stranger than an untranslated
  /// one. Teams whose translations arrive after the code need this.
  final bool fillMissingFromBase;

  /// Whether each locale gets its own generated file.
  ///
  /// Off by default. On, the library is split into a shared file holding the
  /// enums and interfaces and one `part` per locale, so editing a Russian
  /// string rewrites only the Russian file. The import an application writes
  /// is unchanged either way.
  final bool filePerLocale;

  /// Flutter options.
  final FlutterConfig flutter;

  /// File name of the core generated library.
  String get outputFileName => '${_snakeCase(className)}.g.dart';

  /// File name of the generated Flutter glue.
  String get flutterOutputFileName => '${_snakeCase(className)}_flutter.g.dart';

  /// File name of the `part` holding [localeTag]'s translations.
  String localeOutputFileName(String localeTag) =>
      '${_snakeCase(className)}_$localeTag.g.dart';

  /// Parses [content] of a config file located at [uri].
  ///
  /// Returns `null` when the configuration is unusable.
  static L10nPlusConfig? parse(
    String content, {
    required Uri uri,
    required DiagnosticCollector diagnostics,
  }) {
    final YamlNode document;
    try {
      document = loadYamlNode(content, sourceUrl: uri);
    } on YamlException catch (error) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_config',
          message: 'Could not parse the configuration: ${error.message}.',
          span: error.span,
        ),
      );
      return null;
    }

    if (document is! YamlMap) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_config',
          message: 'The configuration must be a YAML map.',
          span: document.span,
        ),
      );
      return null;
    }

    const knownKeys = {
      'input_directory',
      'output_directory',
      'base_locale',
      'fallback_locale',
      'class_name',
      'locale_enum_name',
      'format_plural_numbers',
      'file_pattern',
      'file_per_locale',
      'fill_missing_from_base',
      'flutter',
    };
    for (final key in document.keys) {
      if (knownKeys.contains(key)) continue;
      diagnostics.add(
        Diagnostic.warning(
          code: 'unknown_config_key',
          message: 'Unknown configuration key "$key".',
          span: document.nodes[key]?.span ?? document.span,
          details: 'Known keys: ${(knownKeys.toList()..sort()).join(', ')}.',
        ),
      );
    }

    final baseLocale = _locale(
      document,
      'base_locale',
      diagnostics,
      required: true,
    );
    if (baseLocale == null) return null;

    final fallbackLocale =
        _locale(document, 'fallback_locale', diagnostics) ?? baseLocale;

    final flutterNode = document['flutter'];
    var flutter = const FlutterConfig();
    if (flutterNode is YamlMap) {
      flutter = FlutterConfig(
        enabled: _bool(flutterNode, 'enabled', diagnostics) ?? true,
        contextExtension:
            _string(flutterNode, 'context_extension', diagnostics) ?? 'l10n',
      );
    } else if (flutterNode != null) {
      diagnostics.add(
        Diagnostic.warning(
          code: 'invalid_config',
          message: 'The "flutter" key must be a map. Using defaults.',
          span: document.nodes['flutter']?.span ?? document.span,
        ),
      );
    }

    final className =
        _string(document, 'class_name', diagnostics) ?? 'AppLocalizations';
    final localeEnumName =
        _string(document, 'locale_enum_name', diagnostics) ?? 'AppLocale';

    for (final entry in {
      'class_name': className,
      'locale_enum_name': localeEnumName,
    }.entries) {
      if (DartIdentifiers.upperCamel(entry.value) != entry.value) {
        diagnostics.add(
          Diagnostic.warning(
            code: 'invalid_config',
            message:
                '"${entry.key}" should be an upper camel case Dart class name.',
            span: document.nodes[entry.key]?.span ?? document.span,
          ),
        );
      }
    }

    return L10nPlusConfig(
      inputDirectory:
          _string(document, 'input_directory', diagnostics) ?? 'translations',
      outputDirectory:
          _string(document, 'output_directory', diagnostics) ?? 'lib/generated',
      baseLocale: baseLocale,
      fallbackLocale: fallbackLocale,
      className: className,
      localeEnumName: localeEnumName,
      formatPluralNumbers:
          _bool(document, 'format_plural_numbers', diagnostics) ?? false,
      filePattern: _filePattern(document, diagnostics),
      filePerLocale: _bool(document, 'file_per_locale', diagnostics) ?? false,
      fillMissingFromBase:
          _bool(document, 'fill_missing_from_base', diagnostics) ?? false,
      flutter: flutter,
    );
  }

  static FilePattern? _filePattern(
    YamlMap map,
    DiagnosticCollector diagnostics,
  ) {
    final value = _string(map, 'file_pattern', diagnostics);
    if (value == null) return null;
    return FilePattern.parse(
      value,
      problem: (reason) => diagnostics.add(
        Diagnostic.error(
          code: 'invalid_config',
          message: '"file_pattern" is not usable: $reason',
          span: map.nodes['file_pattern']?.span ?? map.span,
          details:
              'For example:\n'
              '  {locale}      en.json\n'
              '  app_{locale}  app_en.arb\n'
              '  */{locale}    wallet/en.json\n'
              '  {locale}/*    en/wallet.json',
        ),
      ),
    );
  }

  static L10nLocale? _locale(
    YamlMap map,
    String key,
    DiagnosticCollector diagnostics, {
    bool required = false,
  }) {
    final value = map[key];
    if (value == null) {
      if (required) {
        diagnostics.add(
          Diagnostic.error(
            code: 'invalid_config',
            message: 'Missing required configuration key "$key".',
            span: map.span,
            details: 'For example: $key: en',
          ),
        );
      }
      return null;
    }
    if (value is! String) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_config',
          message: '"$key" must be a locale string such as "en" or "pt_BR".',
          span: map.nodes[key]?.span ?? map.span,
        ),
      );
      return null;
    }
    final locale = L10nLocale.tryParse(value);
    if (locale == null) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_config',
          message: '"$value" is not a valid locale identifier.',
          span: map.nodes[key]?.span ?? map.span,
        ),
      );
    }
    return locale;
  }

  static String? _string(
    YamlMap map,
    String key,
    DiagnosticCollector diagnostics,
  ) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_config',
          message: '"$key" must be a string.',
          span: map.nodes[key]?.span ?? map.span,
        ),
      );
      return null;
    }
    return value;
  }

  static bool? _bool(YamlMap map, String key, DiagnosticCollector diagnostics) {
    final value = map[key];
    if (value == null) return null;
    if (value is! bool) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_config',
          message: '"$key" must be true or false.',
          span: map.nodes[key]?.span ?? map.span,
        ),
      );
      return null;
    }
    return value;
  }

  static String _snakeCase(String value) {
    final words = DartIdentifiers.words(value);
    if (words.isEmpty) return 'l10n';
    return words.map((word) => word.toLowerCase()).join('_');
  }
}

/// Resolves a path against the project root, normalizing separators.
String resolveProjectPath(String root, String relative) =>
    p.normalize(p.join(root, relative));

/// Span pointing at the whole configuration file, used when no node fits.
SourceSpan wholeFileSpan(Uri uri, String content) =>
    SourceFile.fromString(content, url: uri).span(0, 0);
