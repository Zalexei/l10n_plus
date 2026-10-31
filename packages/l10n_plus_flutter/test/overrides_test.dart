import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

// The generated files of the generator's `overrides` golden fixture, imported
// by path. Same reason the rich text test does it: this is the one place in
// the repository that can compile the glue, and importing the golden rather
// than copying it means the file under test is byte for byte the file the
// generator writes and `overrides_golden_test.dart` pins.
import '../../l10n_plus_generator/test/goldens/overrides/app_localizations.g.dart';
import '../../l10n_plus_generator/test/goldens/overrides/app_localizations_flutter.g.dart';

/// A screen that reads its text the way an application does.
class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(context.l10n.auth.login.title),
      Text(context.l10n.wallet.transactions(count: 1)),
      Text(context.l10n.wallet.transactions(count: 5)),
    ],
  );
}

void main() {
  const en = L10nLocale('en');
  const ru = L10nLocale('ru');

  // The store is global, so a bundle left behind by one test would be
  // installed in the next. This is the hazard its documentation names.
  tearDown(L10nOverrides.clear);

  Future<AppLocalizationsController> pump(WidgetTester tester) async {
    final controller = createAppLocalizationsController(
      locale: AppLocale.en,
      systemLocales: const [],
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      L10nScope<AppLocale, AppLocalizations>(
        controller: controller,
        child: const MaterialApp(home: _Screen()),
      ),
    );
    return controller;
  }

  testWidgets('a screen changes text after an install, with no locale switch', (
    tester,
  ) async {
    final controller = await pump(tester);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('1 transaction'), findsOneWidget);
    expect(find.text('5 transactions'), findsOneWidget);

    L10nOverrides.install(en, {
      'auth.login.title': 'Sign in',
      'wallet.transactions': {'one': '# payment', 'other': '# payments'},
    });
    await tester.pump();

    // The locale never changed, and the screen was never rebuilt by anything
    // else: installing is what repainted it.
    expect(controller.locale, AppLocale.en);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
    expect(find.text('1 payment'), findsOneWidget);
    expect(find.text('5 payments'), findsOneWidget);
  });

  testWidgets('clearing puts the compiled text back', (tester) async {
    final controller = await pump(tester);
    L10nOverrides.install(en, {'auth.login.title': 'Sign in'});
    await tester.pump();
    expect(find.text('Sign in'), findsOneWidget);

    controller.clearOverrides(en);
    await tester.pump();
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('a bundle for another locale repaints nothing visible', (
    tester,
  ) async {
    final controller = await pump(tester);
    L10nOverrides.install(ru, {'auth.login.title': 'Вход'});
    await tester.pump();
    expect(find.text('Log in'), findsOneWidget);

    // And it is there waiting when the user switches.
    controller.setLocale(AppLocale.ru);
    await tester.pump();
    expect(find.text('Вход'), findsOneWidget);
  });

  testWidgets('setLocale is still synchronous', (tester) async {
    // The roadmap expected this feature to make it asynchronous. It does not:
    // fetching happens before installing, in the application's own code.
    final controller = await pump(tester);
    L10nOverrides.install(ru, {
      'wallet.transactions': {
        'one': '# платёж',
        'few': '# платежа',
        'many': '# платежей',
        'other': '# платежа',
      },
    });
    controller.setLocale(AppLocale.ru);
    await tester.pump();
    expect(find.text('1 платёж'), findsOneWidget);
    expect(find.text('5 платежей'), findsOneWidget);
  });

  testWidgets('any installer repaints, because the store notifies', (
    tester,
  ) async {
    // The controller has no `installOverrides` of its own: a bundle is
    // installed through the generated `AppLocale.x.installOverrides`, which
    // is where the fingerprint to check it against is a constant. The repaint
    // does not depend on who called — the controller subscribes to the store,
    // not to a method of its own.
    await pump(tester);
    L10nOverrides.install(en, {'auth.login.title': 'Sign in'});
    await tester.pump();
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('a disposed controller hears nothing', (tester) async {
    // `notifyListeners` after `dispose` throws, and installing a bundle while
    // a screen is being torn down is exactly when that would happen.
    final controller = createAppLocalizationsController(
      locale: AppLocale.en,
      systemLocales: const [],
    );
    controller.dispose();
    expect(
      () => L10nOverrides.install(en, {'auth.login.title': 'Sign in'}),
      returnsNormally,
    );
  });
}
