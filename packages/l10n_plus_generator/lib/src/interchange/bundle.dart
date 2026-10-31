import 'package:l10n_plus/l10n_plus.dart';
import 'package:source_span/source_span.dart';

import '../diagnostic.dart';
import '../source/arb_source_parser.dart';
import 'catalog.dart';
import 'csv.dart';

/// A format translations travel in, between this project and everything else.
enum InterchangeFormat {
  /// One file, one row per message, one column per locale.
  ///
  /// What a spreadsheet opens and what a translator working alone wants.
  csv,

  /// One Application Resource Bundle per locale.
  ///
  /// What a translation management system ingests, and what `gen_l10n` and
  /// most vendors already speak.
  arb;

  /// The format named by `--format=<name>`, or `null`.
  static InterchangeFormat? byName(String name) {
    for (final format in values) {
      if (format.name == name) return format;
    }
    return null;
  }

  /// Every spelling `--format` accepts, for a usage message.
  static String get names => values.map((format) => format.name).join(', ');
}

/// One translation in one locale, as an interchange file states it.
final class InterchangeEntry {
  /// Creates an entry.
  const InterchangeEntry({
    required this.localeTag,
    required this.key,
    required this.text,
    this.span,
  });

  /// The locale this text is for, as a file tag.
  final String localeTag;

  /// Full dotted key.
  final String key;

  /// The message exactly as the file states it, ICU and all.
  final String text;

  /// Where the text was, for a diagnostic about it.
  final SourceSpan? span;
}

/// What came back from a translator, in whatever format they sent it.
///
/// Deliberately not a map: the order the file states things in is the order
/// the report prints them, and a translator reading the report wants to see
/// their own file's order rather than ours.
final class InterchangeBundle {
  /// Creates a bundle.
  InterchangeBundle({
    required this.localeTags,
    required this.entries,
    this.keySpans = const {},
  });

  /// Locales the file carried, in the order it carried them.
  final List<String> localeTags;

  /// Every translation the file stated, in file order.
  final List<InterchangeEntry> entries;

  /// Where each key was named, for complaining about the key itself.
  final Map<String, SourceSpan> keySpans;

  /// Reads the CSV `export` writes.
  ///
  /// The header decides what the columns are: `key`, an optional
  /// `description`, and one column per locale. A column whose name is not a
  /// locale is reported and skipped rather than guessed at — a spreadsheet
  /// picks up a stray `Comments` column the moment a human touches the file,
  /// and treating it as a language would write comments into translations.
  static InterchangeBundle? readCsv({
    required String content,
    required Uri uri,
    required DiagnosticCollector diagnostics,
  }) {
    final file = SourceFile.fromString(content, url: uri);
    SourceSpan spanOf(CsvField field) =>
        file.span(field.start, field.end.clamp(field.start, file.length));

    final List<List<CsvField>> records;
    try {
      records = Csv.decode(content);
    } on CsvException catch (error) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_interchange',
          message: 'Could not read the CSV: ${error.message}.',
          span: file.span(
            error.offset.clamp(0, file.length),
            error.offset.clamp(0, file.length),
          ),
        ),
      );
      return null;
    }

    if (records.isEmpty) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_interchange',
          message: 'The CSV is empty.',
          details:
              'The first row names the columns: key, description, and one '
              'column per locale. Export writes it for you.',
        ),
      );
      return null;
    }

    final header = records.first;
    if (header.first.value != keyColumn) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_interchange',
          message:
              'The first column must be named "$keyColumn", not '
              '"${header.first.value}".',
          span: spanOf(header.first),
          details:
              'Export writes the header; keep it. Columns: $keyColumn, '
              '$descriptionColumn, and one per locale.',
        ),
      );
      return null;
    }

    // Column index to locale tag. `description` is read by translators and
    // written by developers, so it is skipped rather than imported.
    final columns = <int, String>{};
    final localeTags = <String>[];
    for (var index = 1; index < header.length; index++) {
      final name = header[index].value;
      if (name == descriptionColumn || name.isEmpty) continue;
      final locale = L10nLocale.tryParse(name);
      if (locale == null) {
        diagnostics.add(
          Diagnostic.warning(
            code: 'unknown_interchange_column',
            message: 'Ignoring column "$name": it is not a locale.',
            span: spanOf(header[index]),
            details:
                'A column is a locale tag such as "en" or "pt_BR", or '
                '"$descriptionColumn". Everything else is left alone.',
          ),
        );
        continue;
      }
      columns[index] = locale.toFileTag();
      localeTags.add(locale.toFileTag());
    }

    final entries = <InterchangeEntry>[];
    final keySpans = <String, SourceSpan>{};
    for (final record in records.skip(1)) {
      final key = record.first.value.trim();
      if (key.isEmpty) continue; // A blank row, which spreadsheets produce.
      keySpans[key] = spanOf(record.first);
      for (final column in columns.entries) {
        if (column.key >= record.length) continue;
        final cell = record[column.key];
        // An empty cell is "no translation supplied", never "translate this
        // to nothing": a translator leaves cells blank, and writing an empty
        // string into an application is never what they meant.
        if (cell.value.isEmpty) continue;
        entries.add(
          InterchangeEntry(
            localeTag: column.value,
            key: key,
            text: cell.value,
            span: spanOf(cell),
          ),
        );
      }
    }

    return InterchangeBundle(
      localeTags: localeTags,
      entries: entries,
      keySpans: keySpans,
    );
  }

  /// Reads one or more ARB bundles, which is what a TMS sends back.
  ///
  /// The ARB parser the generator already has does the reading, so a bundle
  /// that works as a translation source works here too: `@@locale`, dotted
  /// keys, metadata, the lot.
  static InterchangeBundle? readArb({
    required List<({Uri uri, String content})> files,
    required DiagnosticCollector diagnostics,
  }) {
    const parser = ArbSourceParser();
    final entries = <InterchangeEntry>[];
    final keySpans = <String, SourceSpan>{};
    final localeTags = <String>[];

    for (final file in files) {
      final name = file.uri.pathSegments.isEmpty
          ? ''
          : file.uri.pathSegments.last;
      final stem = name.contains('.')
          ? name.substring(0, name.lastIndexOf('.'))
          : name;
      final document = parser.parse(
        content: file.content,
        uri: file.uri,
        localeHint: L10nLocale.tryParse(stem),
        diagnostics: diagnostics,
      );
      if (document == null) continue;

      final tag = document.locale.toFileTag();
      if (!localeTags.contains(tag)) localeTags.add(tag);
      for (final leaf in leavesOf(document.root)) {
        keySpans.putIfAbsent(leaf.path, () => leaf.keySpan);
        entries.add(
          InterchangeEntry(
            localeTag: tag,
            key: leaf.path,
            text: leaf.raw,
            span: leaf.valueSpan,
          ),
        );
      }
    }

    if (entries.isEmpty) {
      diagnostics.add(
        Diagnostic.error(
          code: 'invalid_interchange',
          message: 'No ARB bundle held any message.',
          details:
              'Every file was empty, unreadable or had no locale; see above. '
              'An ARB bundle names its locale with "@@locale", or is named '
              'after it.',
        ),
      );
      return null;
    }

    return InterchangeBundle(
      localeTags: localeTags,
      entries: entries,
      keySpans: keySpans,
    );
  }

  /// Name of the CSV column holding the key.
  static const String keyColumn = 'key';

  /// Name of the CSV column holding the description.
  static const String descriptionColumn = 'description';
}
