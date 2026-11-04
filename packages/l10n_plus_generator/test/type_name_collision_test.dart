import 'package:test/test.dart';

import 'support/fixture.dart';

/// Every generated declaration shares one Dart top level namespace.
///
/// A namespace interface, its per locale implementations and a select enum all
/// compete for the same names, and two declarations of one name is a file that
/// does not compile. The generator used to check only members *within* one
/// namespace, so `auth.login` beside `auth_login` was emitted in silence and
/// the analyzer met it first.
void main() {
  group('namespace interfaces', () {
    test('a dotted path and an underscored key cannot share a name', () {
      const bundle =
          '{"auth": {"login": {"title": "A"}}, "auth_login": {"title": "B"}}';
      final result = runGenerator({'en.json': bundle, 'ru.json': bundle});

      expect(errorsOf(result), ['type_name_collision']);
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.message, contains(r'$AuthLogin'));
      expect(diagnostic.details, contains('auth.login'));
      expect(diagnostic.details, contains('auth_login'));
      // The span points at the second key, which is the one to rename.
      expect(diagnostic.translationKey, 'auth_login');
      expect(result.files, isEmpty);
    });

    test('wallet.settings collides with walletSettings', () {
      const bundle =
          '{"wallet": {"settings": {"title": "A"}}, '
          '"walletSettings": {"title": "B"}}';
      final result = runGenerator({'en.json': bundle, 'ru.json': bundle});

      expect(errorsOf(result), ['type_name_collision']);
      expect(result.diagnostics.single.message, contains(r'$WalletSettings'));
    });

    test('a namespace collides with another namespace\'s locale class', () {
      // `foo` generates `$Foo` plus `$FooEn` and `$FooRu`; the namespace
      // `foo.en` generates `$FooEn` as an interface.
      const bundle = '{"foo": {"en": {"title": "A"}, "bar": "B"}}';
      final result = runGenerator({'en.json': bundle, 'ru.json': bundle});

      expect(errorsOf(result), ['type_name_collision']);
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.message, contains(r'$FooEn'));
      expect(diagnostic.details, contains('en implementation'));
    });

    test('one error per colliding pair, not one per locale', () {
      const bundle =
          '{"auth": {"login": {"title": "A"}}, "auth_login": {"title": "B"}}';
      final result = runGenerator({
        'en.json': bundle,
        'ru.json': bundle,
        'de.json': bundle,
        'fr.json': bundle,
      });

      // Four locales means four implementation classes per namespace; the
      // interface collision is reported once and the implementations are not
      // claimed at all, so the report does not multiply.
      expect(errorsOf(result), ['type_name_collision']);
    });
  });

  group('select enums', () {
    test('an enum and a namespace interface never collide', () {
      // `profile.greeting` + argument `gender` generates the enum
      // `ProfileGreetingGender`. The namespace `profile_greeting.gender`
      // generates `$ProfileGreetingGender` — the `$` prefix on every internal
      // class is what keeps the two apart, and this pins that down.
      const bundle =
          '{"profile": {"greeting": "{gender, select, male{Sir} other{Hi}}"}, '
          '"profile_greeting": {"gender": {"label": "Gender"}}}';
      final result = runGenerator({'en.json': bundle, 'ru.json': bundle});

      expect(errorsOf(result), isEmpty);
      final source = result.files.single.contents;
      expect(source, contains('enum ProfileGreetingGender {'));
      expect(
        source,
        contains(r'abstract interface class $ProfileGreetingGender'),
      );
    });

    test('an enum colliding with a locale implementation is reported', () {
      // The root class generates `AppLocalizationsEn`, which carries no `$`;
      // the message `app.localizations` with an argument called `en` wants
      // exactly that name for its enum.
      final result = runGenerator(
        {
          'en.json':
              '{"app": {"localizations": "{en, select, a{A} other{B}}"}}',
        },
        configYaml: '''
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
flutter:
  enabled: false
''',
      );

      expect(errorsOf(result), contains('enum_name_collision'));
    });

    test('two select arguments generating one enum are reported', () {
      // `a.b` + `c` and `aB` + `c` both want `ABC`.
      final result = runGenerator({
        'en.json':
            '{"a": {"b": "{c, select, x{X} other{Y}}"}, '
            '"aB": "{c, select, x{X} other{Y}}"}',
      });

      expect(errorsOf(result), contains('enum_name_collision'));
    });

    test('a key that starts with a digit still names a usable enum', () {
      // `upperCamelPath` does not escape, so the enum of the key `1` was
      // called `1S`, which is not an identifier at all. The pipeline died
      // inside `dart_style` over its own intermediate Dart, with no
      // diagnostic and exit code 255 -- the one outcome this package is
      // supposed to make impossible.
      final result = runGenerator({
        'en.json': '{"1": "{s, select, a{A} other{B}}"}',
      });

      expect(errorsOf(result), isEmpty);
      expect(result.files.single.contents, contains(r'enum $1S {'));
    });
  });

  group('types the generated code refers to', () {
    // A generated declaration does not *collide* with an imported type, it
    // shadows it: Dart resolves a name to the declaration in the file before
    // anything imported. So `interfaces: {String: ...}` was accepted, and
    // every member the generated code types as `String` came to mean the
    // generated interface instead. Nothing was reported, and the mistake
    // surfaced as `argument_type_not_assignable` in the consumer's code --
    // outside, where this package promises to leave nothing.
    const plans =
        '{"plans": {"free": {"title": "Free"}, "pro": {"title": "Pro"}}}';

    test('a shared interface cannot be called String', () {
      final result = runGenerator(
        {'en.json': plans},
        configYaml:
            '''
$defaultConfigYaml
interfaces:
  String:
    - plans.free
    - plans.pro
''',
      );

      expect(errorsOf(result), ['type_name_collision']);
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.message, contains('String'));
      expect(diagnostic.message, contains('shadow'));
      expect(diagnostic.message, contains('dart:core'));
      expect(diagnostic.details, contains('wins over an import'));
      expect(result.files, isEmpty);
    });

    test('the root class cannot be called List', () {
      final result = runGenerator(
        {'en.json': plans},
        configYaml: '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: List
locale_enum_name: AppLocale
flutter:
  enabled: false
''',
      );

      expect(errorsOf(result), contains('type_name_collision'));
    });

    test('the runtime and Flutter types are reserved too, and intl', () {
      // Seeded whether or not the feature that needs the type is on: turning
      // `flutter` or a formatter on later must not break a name that was
      // legal before.
      for (final name in [
        'L10nLocale',
        'PluralOperands',
        'BaseTranslations',
        'L10nScope',
        'BuildContext',
        'NumberFormat',
        'DateTime',
      ]) {
        final result = runGenerator(
          {'en.json': plans},
          configYaml:
              '''
$defaultConfigYaml
interfaces:
  $name:
    - plans.free
    - plans.pro
''',
        );

        expect(errorsOf(result), [
          'type_name_collision',
        ], reason: '$name was accepted as an interface name.');
      }
    });

    test('a name the generated code never writes is free', () {
      final result = runGenerator(
        {'en.json': plans},
        configYaml:
            '''
$defaultConfigYaml
interfaces:
  Plan:
    - plans.free
    - plans.pro
''',
      );

      expect(errorsOf(result), isEmpty);
      expect(
        result.files.single.contents,
        contains('abstract interface class Plan {'),
      );
    });
  });
}
