import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

import 'l10n/app_l10n.g.dart';
// The Flutter glue is a second library; the README's usage snippet omits it.
import 'l10n/app_l10n_flutter.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Dates are formatted in several features, so the ICU symbols have to be
  // loaded before the first frame.
  await initializeAppL10nFormatting();
  runApp(BigApp(controller: createAppL10nController()));
}

class BigApp extends StatelessWidget {
  const BigApp({required this.controller, super.key});

  final AppL10nController controller;

  @override
  Widget build(BuildContext context) {
    return L10nScope(
      controller: controller,
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.l10nController.locale.flutterLocale,
          supportedLocales: appL10nSupportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const HomePage(),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.onboarding.welcome.subtitle),
        actions: [
          for (final locale in AppLocale.values)
            TextButton(
              key: Key('locale-${locale.name}'),
              onPressed: () => context.l10nController.setLocale(locale),
              child: Text(locale.name),
            ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(key: const Key('plain'), title: Text(t.auth.login.action)),
          ListTile(
            key: const Key('plural'),
            title: Text(t.auth.login.title(count: 5)),
          ),
          ListTile(
            key: const Key('currency'),
            title: Text(t.auth.password.subtitle(amount: 1234.5)),
          ),
          ListTile(
            key: const Key('interpolated'),
            title: Text(t.auth.password.hint(name: 'Alex')),
          ),
          ListTile(
            key: const Key('date'),
            title: Text(t.auth.password.empty(when: DateTime(2026, 3, 14))),
          ),
          ListTile(
            key: const Key('select'),
            title: Text(
              t.wallet.history.error(state: WalletHistoryErrorState.on),
            ),
          ),
          ListTile(
            key: const Key('nested'),
            title: Text(t.wallet.history.hint(count: 21)),
          ),
        ],
      ),
    );
  }
}
