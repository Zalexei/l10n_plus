# Example

For a project that already runs `build_runner`. Otherwise the
[`l10n_plus_generator`](https://pub.dev/packages/l10n_plus_generator) CLI does
the same job with no setup.

`pubspec.yaml`:

```yaml
dependencies:
  l10n_plus: ^0.1.0

dev_dependencies:
  build_runner: ^2.4.0
  l10n_plus_builder: ^0.1.0
```

`l10n_plus.yaml`:

```yaml
base_locale: en
```

`build.yaml` — `build_runner` only tracks `lib/`, `bin/` and `test/` unless
told otherwise:

```yaml
targets:
  $default:
    sources:
      - "lib/**"
      - "translations/**"
      - "l10n_plus.yaml"
      - "pubspec.yaml"
      - "$package$"
```

```bash
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch --delete-conflicting-outputs
```

The output is byte for byte what the CLI writes, and editing a translation
triggers an incremental rebuild.
