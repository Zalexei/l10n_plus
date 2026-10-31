/// One field of one record, and where it was.
///
/// The offsets are kept so that a complaint about a cell can point at the
/// cell. A translator who gets `l10n.csv:214:3` fixes the row; one who gets
/// "an unknown key" goes looking.
final class CsvField {
  /// Creates a field.
  const CsvField({required this.value, required this.start, required this.end});

  /// The decoded text: quotes removed, doubled quotes collapsed.
  final String value;

  /// Offset of the first character of the field, quote included.
  final int start;

  /// Offset just past the last character of the field.
  final int end;
}

/// Thrown when a document is not CSV at all.
final class CsvException implements Exception {
  /// Creates a syntax error at [offset].
  CsvException(this.message, this.offset);

  /// What went wrong.
  final String message;

  /// Where it went wrong.
  final int offset;

  @override
  String toString() => 'CsvException: $message';
}

/// RFC 4180 CSV, read and written without losing a byte.
///
/// `package:csv` would do, but a translation cell is exactly the place where a
/// comma, a quote and a newline all turn up at once — an ICU select branch is
/// full of commas and braces, and a multi line message is ordinary — so the
/// encoding is the feature rather than an implementation detail, and it is
/// worth owning and testing directly.
abstract final class Csv {
  /// Renders [records] with LF line endings and no byte order mark.
  ///
  /// A field is quoted only when it has to be, which keeps a diff of the
  /// exported file readable; a quoted field doubles its quotes. LF rather than
  /// CRLF because the reader accepts both and a repository should not acquire
  /// carriage returns from a tool.
  static String encode(List<List<String>> records) {
    final buffer = StringBuffer();
    for (final record in records) {
      buffer.writeln(record.map(encodeField).join(','));
    }
    return buffer.toString();
  }

  /// Renders one field, quoting it when it would otherwise change meaning.
  static String encodeField(String value) {
    final needsQuotes =
        value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r') ||
        // A field that starts or ends in a space keeps it only inside quotes,
        // because a reader is allowed to trim around a separator.
        value != value.trim();
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  /// Parses [content] into records, keeping every field's offsets.
  ///
  /// A line break is a record separator only outside quotes, so a message
  /// with a newline in it survives. A leading byte order mark is dropped:
  /// spreadsheets add one, and it would otherwise become part of the first
  /// header name.
  static List<List<CsvField>> decode(String content) {
    final text = content.startsWith('﻿') ? content.substring(1) : content;
    // Scanning happens in `text`, but every offset reported has to be an
    // offset into `content` — a span one character out points a translator at
    // the wrong cell.
    final offset = text.length == content.length ? 0 : 1;

    final records = <List<CsvField>>[];
    var index = 0;

    // One pass per record, so that the newline ending the last one does not
    // start an empty record after it — while a blank line in the middle of
    // the file still is a record, which is what a spreadsheet produces and
    // what the caller skips by its empty key.
    while (index < text.length) {
      final fields = <CsvField>[];
      while (true) {
        final field = _field(text, index, offset);
        fields.add(field.value);
        index = field.next;
        if (index < text.length && text[index] == ',') {
          index++;
          continue;
        }
        break;
      }
      // A record ends at CRLF, LF or a bare CR.
      if (index < text.length) {
        index += text.startsWith('\r\n', index) ? 2 : 1;
      }
      records.add(fields);
    }
    return records;
  }

  static ({CsvField value, int next}) _field(
    String text,
    int start,
    int offset,
  ) {
    if (start >= text.length || text[start] != '"') {
      var end = start;
      while (end < text.length &&
          text[end] != ',' &&
          text[end] != '\n' &&
          text[end] != '\r') {
        end++;
      }
      return (
        value: CsvField(
          value: text.substring(start, end),
          start: start + offset,
          end: end + offset,
        ),
        next: end,
      );
    }

    final buffer = StringBuffer();
    var index = start + 1;
    while (true) {
      if (index >= text.length) {
        throw CsvException('Unterminated quoted field', start + offset);
      }
      if (text[index] != '"') {
        buffer.write(text[index]);
        index++;
        continue;
      }
      if (index + 1 < text.length && text[index + 1] == '"') {
        buffer.write('"');
        index += 2;
        continue;
      }
      index++;
      break;
    }
    return (
      value: CsvField(
        value: buffer.toString(),
        start: start + offset,
        end: index + offset,
      ),
      next: index,
    );
  }
}
