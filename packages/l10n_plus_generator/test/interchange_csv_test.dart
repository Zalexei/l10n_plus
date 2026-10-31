import 'package:l10n_plus_generator/l10n_plus_generator.dart';
import 'package:test/test.dart';

/// A translation cell is where every CSV edge case turns up at once.
///
/// An ICU select branch is full of commas, a possessive is full of quotes, a
/// two line message is ordinary, and a spreadsheet adds a byte order mark on
/// the way out. Each of these has lost somebody a translation once.
void main() {
  group('a field survives', () {
    const awkward = [
      'plain',
      '',
      'a, b',
      'quote " inside',
      '"wrapped"',
      'line\nbreak',
      'windows\r\nbreak',
      'bare\rreturn',
      '  leading and trailing  ',
      "It''s a '{'literal brace'}'",
      '{count, plural, =0{No transactions} other{{count} transactions}}',
      '{g, select, male{Mr. {name}} female{Ms. {name}} other{{name}}}',
      'all of it: ",\n"" {a, plural, other{#}}',
    ];

    test('one round trip of its own', () {
      for (final value in awkward) {
        final decoded = Csv.decode(
          Csv.encode([
            [value],
          ]),
        );
        expect(
          decoded.single.single.value,
          value,
          reason: 'lost: ${value.replaceAll('\n', r'\n')}',
        );
      }
    });

    test('a round trip next to every other awkward field', () {
      // Separately each one works; the failures live at the boundaries, where
      // a quote ends a field and a newline ends a record.
      final encoded = Csv.encode([awkward, awkward]);
      final decoded = Csv.decode(encoded);
      expect(decoded, hasLength(2));
      expect(decoded.first.map((field) => field.value), awkward);
      expect(decoded.last.map((field) => field.value), awkward);
    });
  });

  test('a field is quoted only when it has to be', () {
    // The exported file is read by people, and a file where every cell is
    // quoted is a file nobody scans.
    expect(Csv.encodeField('plain'), 'plain');
    expect(Csv.encodeField('Welcome back, {name}'), '"Welcome back, {name}"');
    // No comma, no quote, no newline: nothing to protect it from.
    expect(Csv.encodeField('Balance: {amount}'), 'Balance: {amount}');
    expect(Csv.encodeField('a, b'), '"a, b"');
    expect(Csv.encodeField('a " b'), '"a "" b"');
    expect(Csv.encodeField(' padded '), '" padded "');
  });

  test('CRLF and LF are both record separators', () {
    final crlf = Csv.decode('a,b\r\nc,d\r\n');
    final lf = Csv.decode('a,b\nc,d\n');
    expect(crlf.map((r) => r.map((f) => f.value).toList()), [
      ['a', 'b'],
      ['c', 'd'],
    ]);
    expect(
      lf.map((r) => r.map((f) => f.value).toList()),
      crlf.map((r) => r.map((f) => f.value).toList()),
    );
  });

  test('a byte order mark does not become part of the first column', () {
    // Excel writes one, and without this the header reads "﻿key", which
    // would make every export unreadable the moment a human saved it.
    final decoded = Csv.decode('﻿key,en\na,A\n');
    expect(decoded.first.first.value, 'key');
  });

  test('offsets point at the field, mark or not', () {
    for (final mark in ['', '﻿']) {
      final content = '${mark}key,en\nwallet.a,A\n';
      final decoded = Csv.decode(content);
      final field = decoded.last.first;
      expect(
        content.substring(field.start, field.end),
        'wallet.a',
        reason: 'mark: ${mark.isEmpty ? 'none' : 'present'}',
      );
    }
  });

  test('an unterminated quote is refused rather than guessed at', () {
    expect(() => Csv.decode('key,en\na,"oops\n'), throwsA(isA<CsvException>()));
  });

  test('a trailing newline is not an extra record', () {
    expect(Csv.decode('a\nb\n'), hasLength(2));
    expect(Csv.decode('a\nb'), hasLength(2));
  });
}
