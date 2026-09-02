import 'package:l10n_plus/l10n_plus.dart';
import 'package:test/test.dart';

void main() {
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
}
