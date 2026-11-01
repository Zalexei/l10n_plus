import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

// The generated files of the generator's `deferred` golden fixture, imported
// by path, for the reason the other glue tests do it: this is the one place in
// the repository that can compile the Flutter glue, and importing the golden
// means the files under test are byte for byte the files the generator writes
// and `deferred_golden_test.dart` pins.
import '../../l10n_plus_generator/test/goldens/deferred/app_localizations.g.dart';
import '../../l10n_plus_generator/test/goldens/deferred/app_localizations_flutter.g.dart';

/// A screen that reads its text the way an application does.
class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) => Text(context.l10n.auth.title);
}

/// `deferred_locales` driven through a real widget tree.
///
/// The question here is not whether `load()` works — the generator's own
/// runtime test answers that — but whether an application has to know about
/// it. It does not: the controller starts the load on a switch and repaints
/// when it lands, so switching locales is the call it has always been.
///
/// **A deferred load does not complete under a widget test's fake clock, and
/// starting one there spends the locale.** Measured while writing this file: a
/// `load()` begun in fake async never finishes, and awaiting its future inside
/// [WidgetTester.runAsync] afterwards does not rescue it — `loadLibrary`
/// hands out one future per library, and that one belongs to a zone the test
/// has stopped advancing. So every load here happens inside `runAsync`, and an
/// application writing such a test has to do the same.
///
/// Which is also why there is a locale per concern. A loaded library cannot be
/// unloaded and a half-loaded one cannot be retried, so no two of these tests
/// can share one: `fr` for the frame before the chunk arrives, `ru` for the
/// switch that loads, `de` for the awaited switch, `it` for the disposal.
void main() {
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

  testWidgets('setLocale switches now and repaints when the chunk lands', (
    tester,
  ) async {
    final controller = await pump(tester);
    expect(find.text('Log in'), findsOneWidget);
    expect(AppLocale.ru.isLoaded, isFalse);

    // Nothing in the application asks for the load: the controller starts it
    // on the switch and repaints when it lands.
    await tester.runAsync(() async {
      controller.setLocale(AppLocale.ru);
      while (!AppLocale.ru.isLoaded) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await tester.pump();

    expect(controller.locale, AppLocale.ru);
    expect(find.text('Войти'), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
  });

  testWidgets('the frame before the chunk arrives reads as the fallback', (
    tester,
  ) async {
    // The switch is synchronous, as it always was: the locale is French
    // immediately and the text is not, because the translations are not here.
    // The frame renders the fallback rather than nothing, which is the whole
    // reason the fallback locale is never deferred.
    //
    // No `runAsync` here on purpose — the fake clock is what holds the load
    // open, which makes this the one assertion a widget test gets for free.
    final controller = await pump(tester);
    controller.setLocale(AppLocale.fr);
    await tester.pump();

    expect(controller.locale, AppLocale.fr);
    expect(AppLocale.fr.isLoaded, isFalse);
    expect(find.text('Connexion'), findsNothing);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('setLocaleAsync skips the frame that reads as the fallback', (
    tester,
  ) async {
    final controller = await pump(tester);
    expect(AppLocale.de.isLoaded, isFalse);

    await tester.runAsync(() => controller.setLocaleAsync(AppLocale.de));
    await tester.pump();

    // No intermediate frame to find: the switch happened after the load.
    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
  });

  testWidgets('a controller disposed mid-load notifies nobody', (tester) async {
    // The load finishes on a future, so by then the controller may be gone —
    // which is what a settings screen popped during the download is.
    // Notifying a disposed ChangeNotifier throws, so reaching the end of this
    // test is the assertion.
    await tester.runAsync(() async {
      final controller = createAppLocalizationsController(
        locale: AppLocale.en,
        systemLocales: const [],
      );
      controller.setLocale(AppLocale.it);
      controller.dispose();
      while (!AppLocale.it.isLoaded) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    expect(AppLocale.it.isLoaded, isTrue);
  });

  testWidgets('the fallback locale needs no load at all', (tester) async {
    final controller = await pump(tester);
    expect(AppLocale.en.isLoaded, isTrue);
    controller.setLocale(AppLocale.en);
    await tester.pump();
    expect(find.text('Log in'), findsOneWidget);
  });
}
