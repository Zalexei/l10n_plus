import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_plus_example/generated/app_localizations.g.dart';
import 'package:l10n_plus_example/generated/app_localizations_flutter.g.dart';

/// The controller must open in the device's language.
///
/// Flutter calls `didChangeLocales` when the locale *changes*, never at start
/// up, so a controller built with no system locales at all would resolve to
/// the fallback and the app would open in English on a Russian phone — the
/// documented "omit it to follow the operating system" would be false exactly
/// once, on the first frame, which is the frame the user sees.
void main() {
  tearDown(() {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    dispatcher.clearLocalesTestValue();
  });

  testWidgets('an omitted locale follows the platform at start up', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru')];

    final controller = createAppLocalizationsController();
    addTearDown(controller.dispose);

    expect(controller.locale, AppLocale.ru);
    expect(controller.followsSystemLocale, isTrue);
    expect(controller.translations.auth.login.title, 'Войти');
  });

  testWidgets('the platform list is read in order of preference', (
    tester,
  ) async {
    // Unsupported first, supported second: the second one wins rather than
    // the whole list being abandoned for the fallback.
    tester.platformDispatcher.localesTestValue = const [
      Locale('ja'),
      Locale('ru'),
    ];

    final controller = createAppLocalizationsController();
    addTearDown(controller.dispose);

    expect(controller.locale, AppLocale.ru);
  });

  testWidgets('an unsupported platform locale falls back', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];

    final controller = createAppLocalizationsController();
    addTearDown(controller.dispose);

    expect(controller.locale, AppLocalizations.fallbackLocale);
    expect(controller.followsSystemLocale, isTrue);
  });

  testWidgets('an explicit locale still wins over the platform', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru')];

    final controller = createAppLocalizationsController(locale: AppLocale.en);
    addTearDown(controller.dispose);

    expect(controller.locale, AppLocale.en);
    expect(controller.followsSystemLocale, isFalse);
  });

  testWidgets('an explicit empty list opts out of the platform', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru')];

    final controller = createAppLocalizationsController(
      systemLocales: const [],
    );
    addTearDown(controller.dispose);

    expect(controller.locale, AppLocalizations.fallbackLocale);
  });
}
