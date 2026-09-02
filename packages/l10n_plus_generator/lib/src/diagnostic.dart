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
  final List<Diagnostic> _diagnostics = [];

  /// All diagnostics reported so far, in report order.
  List<Diagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Whether any [Severity.error] was reported.
  bool get hasErrors => _diagnostics.any((d) => d.severity == Severity.error);

  /// Reports [diagnostic].
  void add(Diagnostic diagnostic) => _diagnostics.add(diagnostic);

  /// Reports every diagnostic of [diagnostics].
  void addAll(Iterable<Diagnostic> diagnostics) =>
      _diagnostics.addAll(diagnostics);
}
