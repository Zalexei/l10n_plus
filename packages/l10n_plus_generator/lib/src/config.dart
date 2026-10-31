import 'package:l10n_plus/l10n_plus.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import 'diagnostic.dart';
import 'source/file_pattern.dart';
import 'model/dart_identifiers.dart';

/// What to do with a key a locale has and the base locale does not.
enum ExtraKeys {
  /// Fail the build. The default.
  error,

  /// Report it and leave the key out of generation.
  warn,
}

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
    this.runtimeOverrides = false,
    this.extraKeys = ExtraKeys.error,
    this.ignoreDiagnostics = const {},
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

  /// Whether every message body consults [L10nOverrides] before returning
  /// its literal.
  ///
  /// Off by default, and off costs nothing: with it off the generated file is
  /// byte for byte what it was, which is the only way to offer a runtime path
  /// in a library whose argument is that there is no runtime path.
  ///
  /// On, a message can be reworded without a release — but only reworded. The
  /// plural category is still chosen by the compiled CLDR rules and every
  /// argument is still formatted by `package:intl`, so an override carries the
  /// text of one branch and nothing else. Validate a bundle with
  /// `check-overrides`, which reads the slots this emitted.
  final bool runtimeOverrides;

  /// Whether each locale gets its own generated file.
  ///
  /// Off by default. On, the library is split into a shared file holding the
  /// enums and interfaces and one `part` per locale, so editing a Russian
  /// string rewrites only the Russian file. The import an application writes
  /// is unchanged either way.
  final bool filePerLocale;

  /// What to do with a key a locale has and the base locale does not.
  ///
  /// An error by default: the base locale is the API contract, and a key
  /// nothing generated can reach is usually a typo. [ExtraKeys.warn] is for
  /// teams whose translations arrive through a TMS, where a key removed from
  /// the base locale keeps coming back from the translators for a while and
  /// nobody can build in the meantime.
  final ExtraKeys extraKeys;

  /// Warning codes this project does not want reported.
  ///
  /// A project of three thousand keys in ten locales can produce two thousand
  /// `missing_plural_category` warnings, all of them saying the same true
  /// thing about a decision the team already made. Without a way to turn them
  /// off the report gets ignored wholesale, which costs more than the warning
  /// was worth.
  ///
  /// Only warnings are ever dropped. A code that is an error here stays an
  /// error, whatever the list says.
  final Set<String> ignoreDiagnostics;

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
      'runtime_overrides',
      'extra_keys',
      'ignore_diagnostics',
      'flutter',
    };
    for (final key in document.keys) {
      if (knownKeys.contains(key)) continue;
      final nearest = _nearestKey('$key', knownKeys);
      diagnostics.add(
        Diagnostic.warning(
          code: 'unknown_config_key',
          message: 'Unknown configuration key "$key".',
          span: document.nodes[key]?.span ?? document.span,
          details:
              '${nearest == null ? '' : 'Did you mean "$nearest"?\n'}'
              'Known keys: ${(knownKeys.toList()..sort()).join(', ')}.',
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
      runtimeOverrides:
          _bool(document, 'runtime_overrides', diagnostics) ?? false,
      extraKeys: _extraKeys(document, diagnostics),
      ignoreDiagnostics: _ignoreDiagnostics(document, diagnostics),
      flutter: flutter,
    );
  }

  /// Reads `ignore_diagnostics`, dropping entries that cannot mean anything.
  ///
  /// A misspelled code and a code that always stops the build are both
  /// reported rather than accepted: silently keeping either would leave the
  /// project believing a warning is off when it is not.
  static Set<String> _ignoreDiagnostics(
    YamlMap map,
    DiagnosticCollector diagnostics,
  ) {
    final node = map['ignore_diagnostics'];
    if (node == null) return const {};
    final span = map.nodes['ignore_diagnostics']?.span ?? map.span;
    if (node is! YamlList) {
      diagnostics.add(
        Diagnostic.warning(
          code: 'invalid_config',
          message: '"ignore_diagnostics" must be a list of diagnostic codes.',
          span: span,
          details:
              'For example:\n'
              '  ignore_diagnostics: [missing_plural_category]',
        ),
      );
      return const {};
    }

    final codes = <String>{};
    for (final entry in node.nodes) {
      final value = entry.value;
      if (value is! String) {
        diagnostics.add(
          Diagnostic.warning(
            code: 'invalid_config',
            message:
                '"ignore_diagnostics" entries must be strings, not '
                '"$value".',
            span: entry.span,
          ),
        );
        continue;
      }
      if (DiagnosticCodes.suppressible.contains(value)) {
        codes.add(value);
        continue;
      }
      diagnostics.add(
        Diagnostic.warning(
          code: 'invalid_config',
          message: DiagnosticCodes.alwaysErrors.contains(value)
              ? 'Diagnostic "$value" is an error and cannot be ignored.'
              : 'Unknown diagnostic code "$value".',
          span: entry.span,
          details: DiagnosticCodes.alwaysErrors.contains(value)
              ? 'An error stops generation, so hiding it would hide the '
                    'reason the build failed. Fix the translation, or change '
                    'the option that makes it an error.'
              : 'Nothing reports "$value", so this entry silences nothing.\n'
                    'Ignorable codes:\n'
                    '${_wrap(DiagnosticCodes.suppressible)}',
        ),
      );
    }
    return codes;
  }

  /// Renders [codes] sorted, two per line, for a diagnostic's details.
  static String _wrap(Set<String> codes) {
    final sorted = codes.toList()..sort();
    final lines = <String>[];
    for (var i = 0; i < sorted.length; i += 2) {
      lines.add('  ${sorted.skip(i).take(2).join(', ')}');
    }
    return lines.join('\n');
  }

  /// Reads `extra_keys`, keeping the strict default when it cannot be read.
  ///
  /// An option the generator does not understand must never be the reason a
  /// build got looser than the project asked for.
  static ExtraKeys _extraKeys(YamlMap map, DiagnosticCollector diagnostics) {
    final node = map['extra_keys'];
    if (node == null) return ExtraKeys.error;
    final span = map.nodes['extra_keys']?.span ?? map.span;
    for (final value in ExtraKeys.values) {
      if (node == value.name) return value;
    }
    diagnostics.add(
      Diagnostic.warning(
        code: 'invalid_config',
        message: '"extra_keys" must be "error" or "warn", not "$node".',
        span: span,
        details:
            'Keeping "error", which is the default.\n'
            '  error  a key the base locale does not have fails the build\n'
            '  warn   it is reported and the key is ignored',
      ),
    );
    return ExtraKeys.error;
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

  /// The known key [written] is most likely a typo of, or `null`.
  ///
  /// Only a genuinely near miss counts: a third of the length, at most three
  /// edits. `file_per_local` gets an answer, `translations` does not, and a
  /// wrong guess is worse than the list of every key that follows it.
  static String? _nearestKey(String written, Set<String> known) {
    String? best;
    var bestDistance = 1 << 30;
    for (final candidate in known) {
      final distance = _editDistance(written, candidate);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    final budget = (written.length / 3).floor().clamp(1, 3);
    return bestDistance <= budget ? best : null;
  }

  /// Levenshtein distance, two rows at a time.
  static int _editDistance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        current[j] = substitution < deletion
            ? (substitution < insertion ? substitution : insertion)
            : (deletion < insertion ? deletion : insertion);
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
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
