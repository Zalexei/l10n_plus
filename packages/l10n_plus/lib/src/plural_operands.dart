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
