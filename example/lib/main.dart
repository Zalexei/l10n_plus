import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

import 'generated/app_localizations.g.dart';
import 'generated/app_localizations_flutter.g.dart';

Future<void> main() async {
  // Date formats need their ICU symbols before the first message is read.
  await initializeAppLocalizationsFormatting();
  runApp(DemoApp(controller: createAppLocalizationsController()));
}

/// Demo application showing generated translations and locale switching.
class DemoApp extends StatelessWidget {
  /// Creates the demo app.
  const DemoApp({required this.controller, super.key});

  /// Drives the active locale.
  final AppLocalizationsController controller;

  @override
  Widget build(BuildContext context) {
    return L10nScope(
      controller: controller,
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.l10nController.locale.flutterLocale,
          supportedLocales: appLocalizationsSupportedLocales,
          // l10n_plus does not translate Flutter's own widgets; that stays
          // the job of the standard delegates.
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const DemoPage(),
        ),
      ),
    );
  }
}

/// Shows one message of every supported ICU shape.
class DemoPage extends StatelessWidget {
  /// Creates the demo page.
  const DemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    // A single lookup; `t` is a const object, so this allocates nothing.
    final t = context.l10n;
    final controller = context.l10nController;

    return Scaffold(
      appBar: AppBar(title: Text(t.auth.login.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.auth.login.subtitle(name: 'Alex')),
          Text(t.wallet.balance(amount: r'$100')),
          for (final count in [0, 1, 2, 5, 21])
            Text(t.wallet.transactions(count: count)),
          Text(t.wallet.summary(count: 3)),
          Text(t.wallet.total(amount: 1234.5)),
          Text(t.wallet.statement(from: DateTime(2026, 3, 14))),
          Text(t.wallet.price(amount: 1234.5)),
          Text(t.wallet.localPrice(amount: 1234.5)),
          Text(t.wallet.symbolPrice(amount: 1234.5)),
          Text(
            t.profile.greeting(
              name: 'Alex',
              gender: ProfileGreetingGender.male,
            ),
          ),
          const SizedBox(height: 24),
          SegmentedButton<AppLocale>(
            segments: [
              for (final locale in AppLocalizations.supportedLocales)
                ButtonSegment(
                  value: locale,
                  label: Text(locale.l10nLocale.toLanguageTag()),
                ),
            ],
            selected: {controller.locale},
            onSelectionChanged: (selection) =>
                controller.setLocale(selection.first),
          ),
        ],
      ),
    );
  }
}
