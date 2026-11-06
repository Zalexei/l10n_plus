# l10n_plus_builder

A `build_runner` adapter over
[`l10n_plus_generator`](https://pub.dev/packages/l10n_plus_generator), for
projects that already run `build_runner`.

**Optional.** The CLI is the primary workflow; this exists so that generation
takes part in an existing build, and so `build_runner` rebuilds when a
translation file changes.

```yaml
dev_dependencies:
  build_runner: ^2.4.0
  l10n_plus_builder: ^0.1.0
```

`build_runner` tracks `lib/`, `bin/` and `test/` by default, so the
translation directory and the configuration file have to be declared:

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

`build_runner` also declares output extensions statically, and the set of
locales is only known once the translations are read. With
`file_per_locale: true`, list the outputs:

```yaml
    builders:
      l10n_plus_builder:l10n_plus:
        options:
          outputs:
            - "lib/generated/app_localizations.g.dart"
            - "lib/generated/app_localizations_en.g.dart"
            - "lib/generated/app_localizations_flutter.g.dart"
```

Miss one and the builder names the file it wanted to write.

Full guide: **the [repository README](https://github.com/Zalexei/l10n_plus#readme).**
