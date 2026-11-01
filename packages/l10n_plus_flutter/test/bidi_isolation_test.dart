import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The premise `bidi_isolation` rests on, laid out and measured.
///
/// The option emits U+2068 and U+2069 around every interpolated value, and the
/// claim is that without them a value is reordered against the words around it.
/// That claim is about text layout, not about strings, so asserting that the
/// generator emitted two code points would prove nothing. These tests lay the
/// text out with a real `TextPainter` and read the positions back.
///
/// Every case here was measured before the option was written, which is also
/// how the two cases this does *not* fix were found: an LTR value in
/// parentheses inside a Hebrew sentence, and an RTL value in parentheses inside
/// an English one, both of which the bidi algorithm already gets right.
void main() {
  // Built from code points rather than written as literals: this package
  // enables `text_direction_code_point_in_literal`, and rightly — a
  // direction control sitting in source is how a patch is made to read as
  // something it is not. Generated code carries the same two characters as
  // `\u{2068}` escapes, under the `type=lint` header every generated file
  // already has.
  final fsi = String.fromCharCode(0x2068);
  final pdi = String.fromCharCode(0x2069);

  /// The characters of [text] in the order they are laid out, left to right.
  ///
  /// One box per code unit, sorted by left edge, with the isolates themselves
  /// left out — they take part in the algorithm and occupy no width, and a
  /// dump that showed them could not be compared against the value that was
  /// interpolated. A bidi reordering is exactly a difference between this and
  /// the string, which makes it the one thing worth asserting.
  String visualOrder(String text, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 10)),
      textDirection: direction,
    )..layout();
    final placed = <(double, String)>[];
    for (var index = 0; index < text.length; index++) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1),
      );
      if (boxes.isEmpty) continue;
      final character = text[index];
      if (character == fsi || character == pdi) continue;
      placed.add((boxes.first.left, character));
    }
    placed.sort((a, b) => a.$1.compareTo(b.$1));
    return placed.map((entry) => entry.$2).join();
  }

  group('a left to right value in a Hebrew sentence', () {
    // The value is Latin, so it is laid out left to right and must appear in
    // the line exactly as it was written. When it does not, the words of the
    // value have been moved apart by the sentence around them.
    const cases = {
      'ending in a full stop': ('שלום NAME בוקר', 'Ada.'),
      'beginning with digits': ('יש NAME פריטים', '3 Ada'),
      'a negative percentage': ('עלה NAME היום', '-5%'),
    };

    for (final entry in cases.entries) {
      final (template, value) = entry.value;

      test('${entry.key} is reordered without the isolates', () {
        final plain = template.replaceAll('NAME', value);
        expect(
          visualOrder(plain, TextDirection.rtl),
          isNot(contains(value)),
          reason: 'the defect the option exists for is not reproduced',
        );
      });

      test('${entry.key} survives with them', () {
        final isolated = template.replaceAll('NAME', '$fsi$value$pdi');
        expect(visualOrder(isolated, TextDirection.rtl), contains(value));
      });
    }
  });

  test('two values keep the reading order of the sentence', () {
    // Not a repair this time but a decision, and the isolated one is the
    // sentence's: in a right to left line the first placeholder is read first,
    // so it is the rightmost. Without the isolates the separator between two
    // Latin values joins them into one left to right run, and the sentence's
    // first value is read last.
    const template = 'FIRST - SECOND';
    final plain = template
        .replaceAll('FIRST', 'Ada')
        .replaceAll('SECOND', 'Bob');
    final isolated = template
        .replaceAll('FIRST', '${fsi}Ada$pdi')
        .replaceAll('SECOND', '${fsi}Bob$pdi');

    final before = visualOrder(plain, TextDirection.rtl);
    expect(before.indexOf('Ada'), lessThan(before.indexOf('Bob')));

    final after = visualOrder(isolated, TextDirection.rtl);
    expect(after.indexOf('Bob'), lessThan(after.indexOf('Ada')));
  });

  test('a left to right line is reordered the same way, mirrored', () {
    const template = 'FIRST - SECOND';
    final plain = template
        .replaceAll('FIRST', 'שרה')
        .replaceAll('SECOND', 'דנה');
    final isolated = template
        .replaceAll('FIRST', '$fsiשרה$pdi')
        .replaceAll('SECOND', '$fsiדנה$pdi');

    // Hebrew is laid out right to left, so each name's own characters are
    // reversed in this dump; what is asserted is which name comes first.
    final before = visualOrder(plain, TextDirection.ltr);
    expect(before.indexOf('הנד'), lessThan(before.indexOf('הרש')));

    final after = visualOrder(isolated, TextDirection.ltr);
    expect(after.indexOf('הרש'), lessThan(after.indexOf('הנד')));
  });

  test('the isolates cost nothing to lay out', () {
    // They are formatting characters: they take part in the algorithm and get
    // no box of their own, so an isolated value is not wider than a bare one.
    double width(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: const TextStyle(fontSize: 10)),
        textDirection: TextDirection.rtl,
      )..layout();
      return painter.width;
    }

    expect(width('שלום ${fsi}Ada$pdi בוקר'), width('שלום Ada בוקר'));
  });
}
