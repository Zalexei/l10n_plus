# Example

`pubspec.yaml`:

```yaml
dependencies:
  l10n_plus: ^0.1.0
  l10n_plus_flutter: ^0.1.0   # Flutter apps only

dev_dependencies:
  l10n_plus_generator: ^0.1.0
```

`l10n_plus.yaml` — one line is required:

```yaml
base_locale: en
```

`translations/en.json` and `translations/ru.json`:

```json
{
  "auth": { "login": { "title": "Log in", "subtitle": "Welcome back, {name}" } },
  "cart": "{count, plural, =0{Empty} one{# item} other{# items}}"
}
```

```json
{
  "auth": { "login": { "title": "Войти", "subtitle": "С возвращением, {name}" } },
  "cart": "{count, plural, =0{Пусто} one{# товар} few{# товара} many{# товаров} other{# товара}}"
}
```

Generate, and again on every change:

```bash
dart run l10n_plus_generator generate --watch
```

Use it:

```dart
import 'generated/app_localizations.g.dart';

void main() {
  final t = AppLocalizations.forLocale(AppLocale.ru);
  print(t.auth.login.subtitle(name: 'Ада')); // С возвращением, Ада
  print(t.cart(count: 3));                   // 3 товара
}
```

A missing key, a wrong argument or a plural without its branches fails the
build, not the app. In CI:

```bash
dart run l10n_plus_generator analyze
```

A complete Flutter app is in
[`example/`](https://github.com/Zalexei/l10n_plus/tree/main/example) of the
repository.
