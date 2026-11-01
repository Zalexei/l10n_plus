import 'package:source_span/source_span.dart';

/// How bad a [Diagnostic] is.
enum Severity {
  /// Blocks code generation.
  error,

  /// Reported, but generation continues.
  warning,
}

/// A single problem found while reading, parsing or validating translations.
///
/// Diagnostics are the product surface of the generator: they are what a
/// developer sees when a translation is broken, so they carry a stable [code],
/// a one line [message], an optional [span] and optional multi line [details].
final class Diagnostic {
  /// Creates a diagnostic.
  const Diagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.span,
    this.translationKey,
    this.details,
  });

  /// Creates an [Severity.error] diagnostic.
  const Diagnostic.error({
    required String code,
    required String message,
    SourceSpan? span,
    String? translationKey,
    String? details,
  }) : this(
         severity: Severity.error,
         code: code,
         message: message,
         span: span,
         translationKey: translationKey,
         details: details,
       );

  /// Creates a [Severity.warning] diagnostic.
  const Diagnostic.warning({
    required String code,
    required String message,
    SourceSpan? span,
    String? translationKey,
    String? details,
  }) : this(
         severity: Severity.warning,
         code: code,
         message: message,
         span: span,
         translationKey: translationKey,
         details: details,
       );

  /// Severity of the problem.
  final Severity severity;

  /// Stable machine readable identifier, e.g. `missing_key`.
  final String code;

  /// Single line summary.
  final String message;

  /// Where the problem is, when known.
  final SourceSpan? span;

  /// Dotted translation key the problem belongs to, when known.
  final String? translationKey;

  /// Additional lines explaining the expectation versus what was found.
  final String? details;

  /// Renders the diagnostic for a terminal.
  ///
  /// When [highlight] is true and a span is available, the offending source
  /// line is printed with a caret underneath.
  String format({bool highlight = true}) {
    final buffer = StringBuffer();
    final span = this.span;
    if (span != null) {
      final start = span.start;
      buffer.writeln(
        '${_describeUrl(start.sourceUrl)}'
        ':${start.line + 1}:${start.column + 1}',
      );
    }
    if (translationKey != null) buffer.writeln(translationKey);
    buffer.writeln('${severity.name}[$code]: $message');
    if (details != null && details!.isNotEmpty) {
      for (final line in details!.trimRight().split('\n')) {
        buffer.writeln('  $line');
      }
    }
    if (highlight && span != null) {
      buffer.writeln(span.highlight());
    }
    return buffer.toString().trimRight();
  }

  /// Renders [url] for a terminal.
  ///
  /// Only `file:` URIs have a file path; a build asset URI must be printed as
  /// it is rather than crashing the report.
  static String _describeUrl(Uri? url) {
    if (url == null) return '<unknown>';
    if (url.scheme.isEmpty || url.scheme == 'file') return url.toFilePath();
    return url.toString();
  }

  @override
  String toString() => format(highlight: false);
}

/// Mutable sink diagnostics are reported to while a pipeline stage runs.
final class DiagnosticCollector {
  /// Creates a collector that drops warnings whose code is in [ignoredCodes].
  DiagnosticCollector({Set<String> ignoredCodes = const {}})
    : _ignored = {...ignoredCodes};

  final List<Diagnostic> _diagnostics = [];
  final Set<String> _ignored;
  int _ignoredCount = 0;

  /// All diagnostics reported so far, in report order.
  List<Diagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Whether any [Severity.error] was reported.
  bool get hasErrors => _diagnostics.any((d) => d.severity == Severity.error);

  /// How many warnings were dropped because their code is ignored.
  ///
  /// Reported by the CLI: a silenced warning nobody remembers silencing is a
  /// worse problem than the warning was.
  int get ignoredCount => _ignoredCount;

  /// Stops reporting warnings with these [codes].
  ///
  /// Called once the configuration has been read. Diagnostics added before
  /// that — the complaints about the configuration itself — are kept, so a
  /// broken `ignore_diagnostics` cannot hide the report that says so.
  void ignore(Iterable<String> codes) => _ignored.addAll(codes);

  /// Reports [diagnostic], unless it is an ignored warning.
  void add(Diagnostic diagnostic) {
    // Severity is checked here rather than when the list is built, so that a
    // code which is a warning in one configuration and an error in another
    // can be ignored in its warning form only.
    if (diagnostic.severity == Severity.warning &&
        _ignored.contains(diagnostic.code)) {
      _ignoredCount++;
      return;
    }
    _diagnostics.add(diagnostic);
  }

  /// Reports every diagnostic of [diagnostics].
  void addAll(Iterable<Diagnostic> diagnostics) => diagnostics.forEach(add);
}

/// Every diagnostic code the generator can report.
///
/// The list exists for `ignore_diagnostics`, which has to tell a code that
/// does not exist from one that does — a silently misspelled entry would
/// leave the warning it was meant to silence in place and say nothing.
///
/// It is checked against the source by `diagnostic_codes_test.dart`, so a new
/// code that is never registered here fails the build rather than becoming
/// something no project can configure.
abstract final class DiagnosticCodes {
  /// Codes that are only ever an error.
  ///
  /// Nothing can silence these: they stop generation, so hiding one would
  /// hide the reason the build failed.
  static const Set<String> alwaysErrors = {
    'argument_collision',
    'argument_kind_conflict',
    'argument_kind_mismatch',
    'conflicting_currency_code',
    'conflicting_key_kind',
    'duplicate_key',
    'duplicate_override_locale',
    'empty_key',
    'enum_name_collision',
    'extra_placeholder',
    'icu_duplicate_branch',
    'icu_invalid_branch',
    'icu_invalid_currency_code',
    'icu_invalid_style',
    'icu_missing_argument_name',
    'icu_missing_argument_type',
    'icu_missing_branches',
    'icu_missing_other_branch',
    'icu_nesting_too_deep',
    'icu_unbalanced_brace',
    'icu_unclosed_argument',
    'icu_unexpected_currency_code',
    'icu_unsupported_offset',
    'icu_unsupported_type',
    'identifier_collision',
    'invalid_argument_name',
    'invalid_currency_code',
    'invalid_interchange',
    'invalid_json',
    'invalid_key',
    'invalid_leaf_type',
    'invalid_locale_attribute',
    'invalid_override',
    'invalid_root',
    'invalid_select_branch',
    'invalid_yaml',
    'key_kind_mismatch',
    'missing_base_locale',
    'missing_fallback_locale',
    'missing_input_directory',
    'missing_override_fingerprint',
    'missing_placeholder',
    'missing_placeholder_format',
    'no_translation_files',
    'orphan_metadata',
    'override_contains_icu',
    'override_fingerprint_mismatch',
    'override_needs_branches',
    'override_rich_unsupported',
    'override_takes_no_branches',
    'override_unexpected_number_sign',
    'plural_type_mismatch',
    'rich_invalid_markup',
    'rich_tag_mismatch',
    'rich_unsupported_choice',
    'select_branch_collision',
    'select_branch_mismatch',
    'type_name_collision',
    'unexpected_currency_code',
    'unexpected_placeholder_format',
    'unknown_ordinal_language',
    'unknown_override_branch',
    'unknown_override_key',
    'unknown_override_locale',
    'unknown_override_placeholder',
    'unknown_plural_language',
    'unsupported_currency_option',
    'unsupported_placeholder_format',
    'unsupported_placeholder_type',
  };

  /// Codes that can be reported as a warning, and so may be ignored.
  ///
  /// Some of them are an error under a different configuration —
  /// `missing_key` is an error until `fill_missing_from_base` is on, and
  /// `extra_key` until `extra_keys: warn`. Listing them here does not make the
  /// error form ignorable: [DiagnosticCollector] drops warnings only.
  static const Set<String> suppressible = {
    'bidi_isolation_off',
    'currency_options_mismatch',
    'dropped_placeholder_format',
    'extra_key',
    'fill_direction_mismatch',
    'format_style_mismatch',
    'ignored_placeholder_type',
    'invalid_config',
    'invalid_metadata',
    'locale_pattern_mismatch',
    'missing_flutter_dependency',
    'missing_intl_dependency',
    'missing_key',
    'missing_plural_category',
    'renamed_key',
    'unknown_config_key',
    'unknown_interchange_column',
    'unknown_interchange_key',
    'unknown_interchange_locale',
    'unknown_metadata_attribute',
    'unplaceable_key',
    'unrecognized_file_name',
    'unsupported_optional_parameter',
    'unused_key',
    'unused_placeholder_declaration',
    'unused_plural_category',
  };

  /// Every code, whatever its severity.
  static Set<String> get all => {...alwaysErrors, ...suppressible};
}
