import 'package:l10n_plus/l10n_plus.dart';
import 'package:test/test.dart';

void main() {
  _formattedTests();
  _integerPathTests();

  test('integers have no visible fraction digits', () {
    final operands = PluralOperands(21);
    expect(operands.n, 21);
    expect(operands.i, 21);
    expect(operands.v, 0);
    expect(operands.w, 0);
    expect(operands.f, 0);
    expect(operands.t, 0);
  });

  test('doubles expose their visible fraction digits', () {
    final operands = PluralOperands(1.50);
    expect(operands.i, 1);
    expect(operands.v, 1);
    expect(operands.f, 5);
  });

  test('trailing zeros are visible in v and f but not in w and t', () {
    final operands = PluralOperands(1.20);
    // `1.20` is indistinguishable from `1.2` as a Dart double.
    expect(operands.v, 1);
    expect(operands.w, 1);
    expect(operands.t, 2);
  });

  test('a whole double is treated as having no fraction digits', () {
    final operands = PluralOperands(1.0);
    expect(operands.i, 1);
    expect(operands.v, 0);
  });

  test('negative numbers use their absolute value', () {
    final operands = PluralOperands(-3);
    expect(operands.n, 3);
    expect(operands.i, 3);
  });

  group('exponential notation', () {
    // `(1e-7).toString()` is `1e-7`, which has no `.` in it at all, so
    // reading the fraction off the string found none: a genuinely fractional
    // number arrived at the rules as `v = 0`, and Russian called 1e-7 `many`
    // where ICU says `other`. Doubles print this way below 1e-6 and from
    // 1e21 up, and the large side has no fraction to speak of, so a negative
    // exponent is the whole case.
    test('a small fraction has visible fraction digits', () {
      final operands = PluralOperands(1e-7);
      expect(operands.i, 0);
      expect(operands.v, 7);
      expect(operands.w, 7);
      expect(operands.f, 1);
      expect(operands.t, 1);
    });

    test('a mantissa with its own digits is expanded, not rounded', () {
      final operands = PluralOperands(1.5e-7);
      expect(operands.v, 8);
      expect(operands.f, 15);
      expect(operands.t, 15);
    });

    test('the digits beyond an int are read modulo, not dropped', () {
      // 1e-300 spells out 300 fraction digits, which no `int` holds. The
      // rules only ever ask `f = 0`, `f = 1`, `f % 10` and `f % 100`, and the
      // last digits answer all four.
      final operands = PluralOperands(1e-300);
      expect(operands.v, 300);
      expect(operands.f, 1);
      expect(operands.t, 1);
    });

    test('digits a double cannot hold are not read as no fraction', () {
      // The same reading, in the formatted factory: `toStringAsFixed(20)` of
      // 0.1 is 0.10000000000000000555, twenty digits that no `int` holds, and
      // `tryParse` answered null -- which was stored as `f = 0`, the operand
      // of a whole number.
      final operands = PluralOperands.formatted(
        0.1,
        minimumFractionDigits: 0,
        maximumFractionDigits: 20,
      );
      expect(operands.v, 20);
      expect(operands.f % 10, 5);
    });

    test('a value a double prints plainly is unchanged', () {
      expect(PluralOperands(1e-6).v, 6);
      expect(PluralOperands(1e-6).f, 1);
    });
  });
}

void _formattedTests() {
  group('PluralOperands.formatted', () {
    PluralOperands currency(num n) => PluralOperands.formatted(
      n,
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    );
    PluralOperands decimal(num n) => PluralOperands.formatted(
      n,
      minimumFractionDigits: 0,
      maximumFractionDigits: 3,
    );

    test('a whole number under a currency has the digits it displays', () {
      // The case the whole decision is about: `1` renders as `USD1.00`, and
      // CLDR reads that as `other` in English, not `one`.
      final operands = currency(1);
      expect(operands.i, 1);
      expect(operands.v, 2);
      expect(operands.w, 0);
      expect(operands.f, 0);
      expect(operands.t, 0);
    });

    test('trailing zeros count for v and not for w', () {
      // `1.5` under a currency prints `1.50`.
      final operands = currency(1.5);
      expect(operands.v, 2);
      expect(operands.w, 1);
      expect(operands.f, 50);
      expect(operands.t, 5);
    });

    test('the maximum rounds, and the rounded value is what is read', () {
      final operands = decimal(1.23456);
      expect(operands.v, 3);
      expect(operands.w, 3);
      expect(operands.f, 235, reason: 'rounded, not truncated');
      expect(operands.n, 1.235);
    });

    test('rounding can carry into the integer part', () {
      final operands = PluralOperands.formatted(
        1.99,
        minimumFractionDigits: 0,
        maximumFractionDigits: 0,
      );
      expect(operands.i, 2);
      expect(operands.n, 2);
      expect(operands.v, 0);
    });

    test('a decimal pattern leaves a whole number whole', () {
      final operands = decimal(1);
      expect(operands.v, 0);
      expect(operands.w, 0);
      expect(operands.i, 1);
    });

    test('it agrees with the value based operands where it should', () {
      // Nothing is rounded or padded here, so the two must not disagree.
      for (final value in [0, 1, 2, 17, 1.5, 2.25, 0.125]) {
        final formatted = decimal(value);
        final plain = PluralOperands(value);
        expect(formatted.v, plain.v, reason: '$value');
        expect(formatted.w, plain.w, reason: '$value');
        expect(formatted.i, plain.i, reason: '$value');
      }
    });

    test('a negative number uses its absolute value, as CLDR says', () {
      expect(currency(-3).i, 3);
      expect(currency(-3).v, 2);
    });

    test('bounds outside what toStringAsFixed takes do not throw', () {
      expect(
        PluralOperands.formatted(
          1,
          minimumFractionDigits: 0,
          maximumFractionDigits: 99,
        ).i,
        1,
      );
      // Past 1e21 `toStringAsFixed` goes exponential; the value decides.
      expect(
        PluralOperands.formatted(
          1e22,
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        ).v,
        0,
      );
    });
  });
}

void _integerPathTests() {
  group('PluralOperands.formatted on an integer', () {
    test('is exact for values a double cannot hold', () {
      // 2^53 + 1 survives as an int and does not as a double, and CLDR rules
      // read `i % 100`, so losing the low digits changes the category.
      const huge = 9007199254740993;
      final operands = PluralOperands.formatted(
        huge,
        minimumFractionDigits: 0,
        maximumFractionDigits: 3,
      );
      expect(operands.i, huge);
      expect(operands.i % 100, huge % 100);
    });

    test('a minimum still pads the visible digits', () {
      final operands = PluralOperands.formatted(
        7,
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      );
      expect(operands.i, 7);
      expect(operands.v, 2);
      expect(operands.w, 0);
      expect(operands.f, 0);
      expect(operands.t, 0);
    });

    test('it agrees with the double path where both are exact', () {
      for (final value in [0, 1, 2, 11, 101, 1500]) {
        for (final digits in [0, 2, 3]) {
          final asInt = PluralOperands.formatted(
            value,
            minimumFractionDigits: digits,
            maximumFractionDigits: digits,
          );
          final asDouble = PluralOperands.formatted(
            value.toDouble(),
            minimumFractionDigits: digits,
            maximumFractionDigits: digits,
          );
          final reason = '$value at $digits digits';
          expect(asInt.i, asDouble.i, reason: reason);
          expect(asInt.v, asDouble.v, reason: reason);
          expect(asInt.w, asDouble.w, reason: reason);
          expect(asInt.f, asDouble.f, reason: reason);
          expect(asInt.t, asDouble.t, reason: reason);
        }
      }
    });
  });
}
