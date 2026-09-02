import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_plus_example/generated/app_localizations.g.dart';
import 'package:l10n_plus_example/generated/app_localizations_flutter.g.dart';
import 'package:l10n_plus_example/main.dart';

void main() {
  testWidgets('switching the locale rebuilds the UI', (tester) async {
    final controller = createAppLocalizationsController(locale: AppLocale.en);
    addTearDown(controller.dispose);

    await tester.pumpWidget(DemoApp(controller: controller));

    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Welcome back, Alex'), findsOneWidget);
    expect(find.text('No transactions'), findsOneWidget);
    expect(find.text('1 transaction'), findsOneWidget);
    expect(find.text('5 transactions'), findsOneWidget);
    expect(find.text('Welcome, Mr. Alex'), findsOneWidget);

    controller.setLocale(AppLocale.ru);
    await tester.pumpAndSettle();

    expect(find.text('Войти'), findsWidgets);
    expect(find.text('С возвращением, Alex'), findsOneWidget);
    expect(find.text('Нет транзакций'), findsOneWidget);
    expect(find.text('1 транзакция'), findsOneWidget);
    expect(find.text('2 транзакции'), findsOneWidget);
    expect(find.text('5 транзакций'), findsOneWidget);
    expect(find.text('21 транзакция'), findsOneWidget);
  });

  testWidgets('reading translations without a scope explains what to do', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Text(context.l10n.auth.login.title),
        ),
      ),
    );
    expect(tester.takeException(), isA<FlutterError>());
  });

  test('translations are reachable without a BuildContext', () {
    final t = AppLocalizations.forLocale(AppLocale.ru);
    expect(t.wallet.balance(amount: '100'), 'Баланс: 100');
    expect(t.appLocale, AppLocale.ru);
  });

  test('unsupported locales fall back through the chain', () {
    expect(AppLocalizations.resolve(L10nLocale.parse('ru_RU')), AppLocale.ru);
    expect(AppLocalizations.resolve(L10nLocale.parse('de')), AppLocale.en);
    expect(AppLocalizations.resolve(null), AppLocale.en);
  });

  test('namespace access allocates no new objects', () {
    final t = AppLocalizations.forLocale(AppLocale.en);
    expect(identical(t.auth.login, t.auth.login), isTrue);
    expect(identical(t.auth, t.auth), isTrue);
  });
}
