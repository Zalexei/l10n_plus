import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

// The generator's `current` golden — `global_translations: true` — imported by
// path for the reason `overrides_test.dart` gives: this package is the one
// that can compile the glue, and the file under test is then byte for byte
// the generated one.
import '../../l10n_plus_generator/test/goldens/current/app_localizations.g.dart';
import '../../l10n_plus_generator/test/goldens/current/app_localizations_flutter.g.dart';

/// A screen that reads both ways, so a test can see them agree.
class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('context: ${context.l10n.auth.login.title}'),
      Text('current: ${AppLocalizations.current.auth.login.title}'),
    ],
  );
}

void main() {
  tearDown(AppLocalizations.resetCurrent);

  final enTitle = AppLocalizations.forLocale(AppLocale.en).auth.login.title;
  final ruTitle = AppLocalizations.forLocale(AppLocale.ru).auth.login.title;

  AppLocalizationsController create({
    AppLocale? locale,
    List<Locale> systemLocales = const [],
  }) {
    final controller = createAppLocalizationsController(
      locale: locale,
      systemLocales: systemLocales,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('a new controller installs its locale', () {
    create(locale: AppLocale.ru);
    expect(AppLocalizations.currentLocale, AppLocale.ru);
  });

  test('the system locale it resolved is current from the start', () {
    create(systemLocales: const [Locale('ru', 'RU')]);
    expect(AppLocalizations.currentLocale, AppLocale.ru);
  });

  test('setLocale, useSystemLocale and a system change move current', () {
    final controller = create(locale: AppLocale.en);

    controller.setLocale(AppLocale.ru);
    expect(AppLocalizations.currentLocale, AppLocale.ru);

    controller.useSystemLocale(const [L10nLocale('en')]);
    expect(AppLocalizations.currentLocale, AppLocale.en);

    controller.handleSystemLocalesChanged(const [L10nLocale('ru')]);
    expect(AppLocalizations.currentLocale, AppLocale.ru);
  });

  test('a listener already sees the new locale in current', () {
    final controller = create(locale: AppLocale.en);
    AppLocale? seen;
    controller.addListener(() => seen = AppLocalizations.currentLocale);
    controller.setLocale(AppLocale.ru);
    expect(seen, AppLocale.ru);
  });

  test('dispose releases it, and the next controller may install', () {
    final first = createAppLocalizationsController(
      locale: AppLocale.ru,
      systemLocales: const [],
    );
    first.dispose();
    expect(AppLocalizations.currentCell.locale, isNull);
    expect(AppLocalizations.currentLocale, AppLocalizations.fallbackLocale);

    create(locale: AppLocale.ru);
    expect(AppLocalizations.currentLocale, AppLocale.ru);
  });

  test('a second live controller fails the assert', () {
    create(locale: AppLocale.en);
    expect(
      () => createAppLocalizationsController(
        locale: AppLocale.ru,
        systemLocales: const [],
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  testWidgets('context.l10n and current agree after a switch', (tester) async {
    final controller = create(locale: AppLocale.en);
    await tester.pumpWidget(
      L10nScope<AppLocale, AppLocalizations>(
        controller: controller,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: _Screen(),
        ),
      ),
    );
    expect(find.text('context: $enTitle'), findsOneWidget);
    expect(find.text('current: $enTitle'), findsOneWidget);

    controller.setLocale(AppLocale.ru);
    await tester.pump();

    expect(find.text('context: $ruTitle'), findsOneWidget);
    expect(find.text('current: $ruTitle'), findsOneWidget);
  });
}
