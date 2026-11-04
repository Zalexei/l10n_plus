/// The CLDR plural operands of a number.
///
/// The generator emits locale specific conditions over these fields, so the
/// runtime never has to carry a plural rule table. See
/// <https://unicode.org/reports/tr35/tr35-numbers.html#Operands>.
final class PluralOperands {
  /// Computes the operands of [n].
  factory PluralOperands(num n) {
    final absolute = n.abs();
    final i = absolute.truncate();
    if (absolute is int || absolute == i) {
      return PluralOperands._(absolute.toDouble(), i, 0, 0, 0, 0);
    }

    final fraction = _fractionDigits(absolute.toDouble());
    final withoutTrailing = fraction.replaceFirst(RegExp(r'0+$'), '');
    return PluralOperands._(
      absolute.toDouble(),
      i,
      fraction.length,
      withoutTrailing.length,
      _digitsAsInt(fraction),
      _digitsAsInt(withoutTrailing),
    );
  }

  /// The fraction digits of [absolute], written out in plain decimal.
  ///
  /// `toString` switches to exponential notation below 1e-6 and from 1e21 up,
  /// and such a string has no `.` in it at all. Reading the digits after the
  /// point therefore found none, and a genuinely fractional number reached
  /// the rules as though it were whole: Russian called 1e-7 `many` where ICU
  /// says `other`. This is not the recorded `1.0 == 1` compromise, which is
  /// about a value a double cannot tell apart; here the value is fractional
  /// and the string was simply not read. The large side cannot arrive here —
  /// a value that big is its own `truncate` — so a negative exponent is the
  /// whole case.
  static String _fractionDigits(double absolute) {
    final text = absolute.toString();
    final exponentAt = text.indexOf('e');
    if (exponentAt < 0) {
      final pointAt = text.indexOf('.');
      return pointAt < 0 ? '' : text.substring(pointAt + 1);
    }
    final exponent = int.parse(text.substring(exponentAt + 1));
    final mantissa = text.substring(0, exponentAt);
    final pointAt = mantissa.indexOf('.');
    final digits = pointAt < 0 ? mantissa : mantissa.replaceFirst('.', '');
    final point = (pointAt < 0 ? mantissa.length : pointAt) + exponent;
    if (point >= digits.length) return '';
    return point <= 0 ? '0' * -point + digits : digits.substring(point);
  }

  /// [digits] read as an integer, from the end.
  ///
  /// A double can spell out a few hundred fraction digits (1e-300 has 300)
  /// and no `int` holds that, so parsing the whole string either throws or,
  /// with `tryParse`, silently answered 0 — which reads as *no* fraction at
  /// all. CLDR's conditions only ever ask `f = 0`, `f = 1`, `f % 10` and
  /// `f % 100`, and the last digits answer all four, so the tail is the whole
  /// answer.
  static int _digitsAsInt(String digits) {
    if (digits.isEmpty) return 0;
    final tail = digits.length > 18
        ? digits.substring(digits.length - 18)
        : digits;
    return int.parse(tail);
  }

  /// Computes the operands of [n] as a formatter will *render* it.
  ///
  /// CLDR defines `v`, `w`, `f` and `t` over the digits the reader sees, not
  /// over the value: `1` shown as `USD1.00` is `other` in English, and the
  /// same `1` shown as `1` is `one`. Only the formatter knows which, so the
  /// generator passes its bounds through — `NumberFormat` exposes them as
  /// `minimumFractionDigits` and `maximumFractionDigits`, and the runtime
  /// stays free of any dependency on it.
  ///
  /// Rendering is reproduced the way `NumberFormat` does it: round to
  /// [maximumFractionDigits], then trim trailing zeros down to
  /// [minimumFractionDigits]. So `1.5` under a currency (2, 2) has `v == 2`
  /// and `w == 1`, exactly as `1.50` does.
  factory PluralOperands.formatted(
    num n, {
    required int minimumFractionDigits,
    required int maximumFractionDigits,
  }) {
    // `toStringAsFixed` is defined for 0..20 digits and goes exponential past
    // 1e21; outside that the value has no visible fraction to speak of, so
    // fall back to reading the value itself.
    final maximum = maximumFractionDigits.clamp(0, 20);
    final minimum = minimumFractionDigits.clamp(0, maximum);
    final absolute = n.abs();
    if (absolute is int) {
      // An integer has no fraction to round, so the formatter can only pad it
      // out to the minimum. Worth the special case twice over: it is the
      // common count, and it keeps `i` exact for values a double cannot hold.
      return PluralOperands._(absolute.toDouble(), absolute, minimum, 0, 0, 0);
    }
    if (absolute >= 1e21 || !absolute.isFinite) return PluralOperands(n);

    final fixed = absolute.toStringAsFixed(maximum);
    final dot = fixed.indexOf('.');
    final integer = dot < 0 ? fixed : fixed.substring(0, dot);
    final fraction = dot < 0 ? '' : fixed.substring(dot + 1);

    final withoutTrailing = fraction.replaceFirst(RegExp(r'0+$'), '');
    // What is actually printed: the significant digits, padded back up to the
    // minimum the formatter guarantees.
    final visible = withoutTrailing.length >= minimum
        ? withoutTrailing
        : fraction.substring(0, minimum);

    return PluralOperands._(
      double.parse(fixed),
      int.tryParse(integer) ?? absolute.truncate(),
      visible.length,
      withoutTrailing.length,
      _digitsAsInt(visible),
      _digitsAsInt(withoutTrailing),
    );
  }

  const PluralOperands._(this.n, this.i, this.v, this.w, this.f, this.t);

  /// Absolute value of the source number.
  final double n;

  /// Integer digits of [n].
  final int i;

  /// Number of visible fraction digits, with trailing zeros.
  final int v;

  /// Number of visible fraction digits, without trailing zeros.
  final int w;

  /// Visible fraction digits, with trailing zeros, as an integer.
  final int f;

  /// Visible fraction digits, without trailing zeros, as an integer.
  final int t;
}
