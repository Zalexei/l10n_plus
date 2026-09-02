// What an unedited TMS export renders, in three states of completeness.
import 'package:tms_import/l10n/strings.g.dart';

Future<void> main() async {
  await initializeStringsFormatting();
  final due = DateTime(2026, 4, 30);
  for (final locale in StringsLocale.values) {
    final t = Strings.forLocale(locale);
    print('--- ${locale.name} ---');
    print(t.billing.invoice.title(number: 'INV-2026-0042'));
    print(t.billing.invoice.total(amount: 1234.5));
    print(t.billing.invoice.dueOn(date: due));
    for (final n in [0, 1, 5]) {
      print('  ${t.billing.invoice.lines(count: n)}');
    }
    print(t.billing.reminder.subject(tone: BillingReminderSubjectTone.legal));
    print(t.account.profile.greeting(name: 'Alex'));
    print(t.account.plan.renews(when: due, price: 99));
    print('');
  }
}
