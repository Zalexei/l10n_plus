# Example

Generate translations with
[`l10n_plus_generator`](https://pub.dev/packages/l10n_plus_generator), then:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:l10n_plus_flutter/l10n_plus_flutter.dart';

import 'generated/app_localizations.g.dart';
import 'generated/app_localizations_flutter.g.dart';

void main() {
  // Opens in the device's language, resolved against your translations.
  runApp(App(controller: createAppLocalizationsController()));
}

class App extends StatelessWidget {
  const App({required this.controller, super.key});

  final AppLocalizationsController controller;

  @override
  Widget build(BuildContext context) => L10nScope(
    controller: controller,
    child: Builder(
      builder: (context) => MaterialApp(
        locale: context.l10nController.locale.flutterLocale,
        supportedLocales: appLocalizationsSupportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Home(),
      ),
    ),
  );
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.auth.login.title)),
    body: Center(child: Text(context.l10n.cart(count: 3))),
    floatingActionButton: FloatingActionButton(
      // Everything that read context.l10n rebuilds in Russian.
      onPressed: () => context.l10nController.setLocale(AppLocale.ru),
      child: const Icon(Icons.translate),
    ),
  );
}
```

A complete app is in
[`example/`](https://github.com/Zalexei/l10n_plus/tree/main/example) of the
repository.
