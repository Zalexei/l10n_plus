// A payments backend rendering a monthly statement in three languages.
// No Flutter anywhere: this file runs on the Dart VM.
import 'package:fintech_statements/l10n/statements.g.dart';

Future<void> main() async {
  await initializeStatementsFormatting();

  const month = 3;
  final period = DateTime(2026, month);

  for (final locale in StatementLocale.values) {
    final t = Statements.forLocale(locale);
    final s = t.statement;
    print('--- ${locale.name} ---');
    print(s.title(month: period));
    print(s.opening(amount: 1234.5));
    print(s.closing(amount: 9876.54));
    print(s.card(amount: 1234.56));
    print(s.yen(amount: 15000));
    print(s.crypto(amount: 0.0125));
    for (final n in [0, 1, 2, 5, 21, 1500]) {
      print('  ${s.txCount(count: n)}');
    }
    for (final state in StatementStatusState.values) {
      print('  ${state.name} -> ${s.status(state: state)}');
    }
    print(s.feeNote(fee: 0.015, n: 3));
    print('');
  }
}
