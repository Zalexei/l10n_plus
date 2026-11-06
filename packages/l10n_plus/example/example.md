# Example

This package is the runtime the generated code imports; you do not call it
directly. Generate translations with
[`l10n_plus_generator`](https://pub.dev/packages/l10n_plus_generator) and use
the API it writes — pure Dart, no Flutter needed:

```dart
import 'generated/app_localizations.g.dart';

void main() {
  final t = AppLocalizations.forLocale(AppLocale.en);
  print(t.auth.login.title);              // Log in
  print(t.cart(count: 3));                // 3 items

  // Pick the best supported locale for a request: pt_BR -> pt -> fallback.
  final u = AppLocalizations.of(L10nLocale.parse('pt_BR'));
  print(u.appLocale);
}
```

`L10nLocale`, which the generated file re-exports, is the one type from here
you are likely to touch:

```dart
L10nLocale.parse('ar-EG').isRightToLeft;   // true
L10nLocale.parse('az-Latn').isRightToLeft; // false
```

Setup, configuration and every feature:
[the repository README](https://github.com/Zalexei/l10n_plus#readme).
