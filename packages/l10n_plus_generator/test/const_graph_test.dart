@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/fixture.dart';

/// The central claim: the object graph is built by the compiler, not at run
/// time, so reading `t.auth.login` walks constants and allocates nothing.
///
/// Until now that was one assertion in the example app, on two accessors of
/// one project. `identical` proves the instance is canonical; it cannot prove
/// the *next* accessor someone adds will be. These read the emitted source
/// instead, so every accessor of every shape is covered, and a `const` the
/// emitter stops writing fails here rather than in someone's frame budget.
const String _config = '''
input_directory: translations
output_directory: lib/generated
base_locale: en
fallback_locale: en
class_name: AppLocalizations
locale_enum_name: AppLocale
flutter:
  enabled: false
''';

/// A project deep and wide enough that a shortcut would show.
const Map<String, String> _project = {
  'en.json': '''
{
  "flat": "Flat",
  "auth": {
    "login": {
      "title": "Log in",
      "deep": {"deeper": {"deepest": "Bottom"}}
    },
    "signup": {"title": "Sign up"}
  },
  "wallet": {
    "total": "Total: {amount, number, currency:USD}",
    "items": "{count, plural, one{# item} other{# items}}",
    "tone": "{t, select, a{A} other{B}}"
  }
}
''',
  'ru.json': '''
{
  "flat": "Плоский",
  "auth": {
    "login": {
      "title": "Войти",
      "deep": {"deeper": {"deepest": "Дно"}}
    },
    "signup": {"title": "Регистрация"}
  },
  "wallet": {
    "total": "Итого: {amount, number, currency:USD}",
    "items": "{count, plural, one{# элемент} few{# элемента} many{# элементов} other{# элемента}}",
    "tone": "{t, select, a{А} other{Б}}"
  }
}
''',
};

/// Every namespace accessor in [source], as `(member, body)`.
///
/// Matches the implementation side only — the interfaces declare accessors
/// without a body, and those are not what allocates.
List<({String member, String body})> _accessors(String source) => [
  for (final match in RegExp(
    r'^  \$\w+ get (\w+) => ([^;]+);',
    multiLine: true,
  ).allMatches(source))
    (member: match.group(1)!, body: match.group(2)!.trim()),
];

void main() {
  late String source;

  setUpAll(() {
    final result = runGenerator(_project, configYaml: _config);
    expect(errorsOf(result), isEmpty);
    source = result.files.single.contents;
  });

  test('every namespace accessor returns a const instance', () {
    final accessors = _accessors(source);
    // Two locales, and per locale: root -> auth, wallet; auth -> login,
    // signup; login -> deep; deep -> deeper.
    expect(accessors, hasLength(12));
    final allocating = [
      for (final accessor in accessors)
        if (!accessor.body.startsWith('const ')) accessor,
    ];
    expect(
      allocating,
      isEmpty,
      reason: 'these build a new object on every read: $allocating',
    );
  });

  test('every implementation class has a const constructor', () {
    // An accessor can only say `const` if the class allows it, so this is the
    // other half of the same guarantee — and the half a new field would break
    // first.
    final classes = RegExp(
      r'^(?:final )?class (\$?\w+(?:En|Ru)) implements',
      multiLine: true,
    ).allMatches(source).map((m) => m.group(1)!).toList();
    expect(classes, isNotEmpty);
    for (final name in classes) {
      expect(
        source,
        contains('const $name();'),
        reason: '$name cannot be const, so nothing holding it can be either',
      );
    }
  });

  test('the locale enum hands out const instances too', () {
    // `AppLocale.en.translations` is the root of every chain; a new object
    // here would allocate on every screen build.
    expect(source, contains('AppLocale.en => const AppLocalizationsEn()'));
    expect(source, contains('AppLocale.ru => const AppLocalizationsRu()'));
  });

  test('a message that formats still allocates only its result', () {
    // The formatters are lazily initialized top level finals, shared by every
    // call. What a message allocates is the string it returns, which is the
    // point of calling it.
    expect(source, contains('final NumberFormat _enNumberCurrencyUsd ='));
    expect(
      RegExp(r'NumberFormat\.currency\(').allMatches(source).length,
      2,
      reason: 'one per locale, not one per call site',
    );
  });

  test('select enums are top level, so no branch allocates', () {
    expect(source, contains('enum WalletToneT {'));
  });
}
