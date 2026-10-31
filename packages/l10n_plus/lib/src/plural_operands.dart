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

    var fraction = absolute.toString().split('.').elementAtOrNull(1) ?? '';
    // `toString` of a double can use exponent notation; bail out to no digits.
    if (!RegExp(r'^[0-9]+$').hasMatch(fraction)) fraction = '';

    final withoutTrailing = fraction.replaceFirst(RegExp(r'0+$'), '');
    return PluralOperands._(
      absolute.toDouble(),
      i,
      fraction.length,
      withoutTrailing.length,
      fraction.isEmpty ? 0 : int.parse(fraction),
      withoutTrailing.isEmpty ? 0 : int.parse(withoutTrailing),
    );
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
      int.tryParse(visible) ?? 0,
      int.tryParse(withoutTrailing) ?? 0,
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
