# l10n_plus_flutter

Flutter integration for [`l10n_plus`](https://pub.dev/packages/l10n_plus).

```dart
void main() => runApp(
  L10nScope(
    controller: createAppLocalizationsController(),
    child: const App(),
  ),
);

class Screen extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Text(context.l10n.auth.login.title);
}
```

What it adds:

* `L10nController` — the single source of truth for the active locale.
  `setLocale` is synchronous, because nothing is loaded asynchronously in
  generated mode.
* `L10nScope` — an `InheritedNotifier` that rebuilds dependents on a change.
* `context.l10n` — the generated extension, named by `context_extension` in
  your configuration.
* `Locale` interop, and system-locale following.

There is deliberately **no `LocalizationsDelegate`**: `L10nScope` is already a
single source of truth, and a delegate would create a second path to the same
state. Add `GlobalMaterialLocalizations.delegates` for Flutter's own widgets —
that is not this package's job.

Full guide and design notes: **the [repository README](https://github.com/Zalexei/l10n_plus#readme) and [`docs/architecture.md`](https://github.com/Zalexei/l10n_plus/blob/main/docs/architecture.md).**
